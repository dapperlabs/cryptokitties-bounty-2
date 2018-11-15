pragma solidity ^0.4.24;

import "./OffersAccessControl.sol";

/// @title Contract that manages configuration values and fee structure for offers.
/// @author Dapper Labs (https://www.dapperlabs.com)
contract OffersConfig is OffersAccessControl {

    /* ************************* */
    /* ADJUSTABLE CONFIGURATIONS */
    /* ************************* */

    // The duration (in seconds) of all offers that are created. This parameter is also used in calculating
    // new expiration times when extending offers.
    uint256 public globalDuration;
    // The global minimum offer value (price + offer fee, in wei)
    uint256 public minimumTotalValue;
    // The minimum overbid increment % (expressed in basis points, which is 1/100 of a percent)
    // For basis points, values 0-10,000 map to 0%-100%
    uint256 public minimumPriceIncrement;

    /* *************** */
    /* ADJUSTABLE FEES */
    /* *************** */

    // Throughout the various contracts there will be various symbols used for the purpose of a clear display
    // of the underlying mathematical formulation. Specifically,
    //
    //          - T: This is the total amount of funds associated with an offer, comprised of 1) the offer
    //                  price which the bidder is proposing the owner of the token receive, and 2) an amount
    //                  that is the maximum the main Offers contract will ever take - this is when the offer
    //                  is cancelled, or fulfilled. In other scenarios, the amount taken by the main contract
    //                  may be less, depending on other configurations.
    //
    //          - S: This is called the offerCut, expressed as a basis point. This determines the maximum amount
    //                  of ether the main contract can ever take in the various possible outcomes of an offer
    //                  (cancelled, expired, overbid, fulfilled, updated).
    //
    //          - P: This simply refers to the price that the bidder is offering the owner receive, upon
    //                  fulfillment of the offer process.
    //
    //          - Below is the formula that ties the symbols listed above together (S is % for brevity):
    //                  T = P + S * P

    // Flat fee (in wei) the main contract takes when offer has been expired or overbid. The fee serves as a
    // disincentive for abuse and allows recoupment of ether spent calling batchRemoveExpired on behalf of users.
    uint256 public unsuccessfulFee;
    // This is S, the maximum % the main contract takes on each offer. S represents the total amount paid when
    // an offer has been fulfilled or cancelled.
    uint256 public offerCut;

    /* ****** */
    /* EVENTS */
    /* ****** */

    event GlobalDurationUpdated(uint256 value);
    event MinimumTotalValueUpdated(uint256 value);
    event MinimumPriceIncrementUpdated(uint256 value);
    event OfferCutUpdated(uint256 value);
    event UnsuccessfulFeeUpdated(uint256 value);

    /* ********* */
    /* FUNCTIONS */
    /* ********* */

    /// @notice Sets the minimumTotalValue value. All offers in existence must have a total value greater than this.
    /// @notice Only callable by COO, when not frozen.
    /// @param _newMinTotal The minimumTotalValue value to set
    function setMinimumTotalValue(uint256 _newMinTotal) external onlyCOO whenNotFrozen {
        _setMinimumTotalValue(_newMinTotal, unsuccessfulFee);
        emit MinimumTotalValueUpdated(_newMinTotal);
    }

    /// @notice Sets the globalDuration value. All offers that are created or updated will compute a new expiration
    ///  time based on this.
    /// @notice Only callable by COO, when not frozen.
    /// @param _newDuration The globalDuration value to set.
    function setGlobalDuration(uint256 _newDuration) external onlyCOO whenNotFrozen {
        globalDuration = _newDuration;
        emit GlobalDurationUpdated(_newDuration);
    }

    /// @notice Sets the offerCut value. All offers will compute a fee taken by this contract based on this
    ///  configuration.
    /// @notice Only callable by COO, when not frozen.
    /// @dev As this configuration is a basis point, the value to set must be less than or equal to 10000.
    /// @param _newOfferCut The offerCut value to set.
    function setOfferCut(uint256 _newOfferCut) external onlyCOO whenNotFrozen {
        _setOfferCut(_newOfferCut);
        emit OfferCutUpdated(_newOfferCut);
    }

    /// @notice Sets the unsuccessfulFee value. All offers that are unsuccessful (overbid or expired)
    ///  will have a flat fee taken by the main contract before being refunded to bidders.
    /// @notice Only callable by COO, when not frozen.
    /// @param _newUnsuccessfulFee The unsuccessfulFee value to set.
    function setUnsuccessfulFee(uint256 _newUnsuccessfulFee) external onlyCOO whenNotFrozen {
        unsuccessfulFee = _newUnsuccessfulFee;
        emit UnsuccessfulFeeUpdated(_newUnsuccessfulFee);
    }

    /// @notice Sets the minimumPriceIncrement value. All offers that are overbid must have a price greater
    ///  than the minimum increment computed from this basis point.
    /// @notice Only callable by COO, when not frozen.
    /// @dev As this configuration is a basis point, the value to set must be less than or equal to 10000.
    /// @param _newMinimumPriceIncrement The minimumPriceIncrement value to set.
    function setMinimumPriceIncrement(uint256 _newMinimumPriceIncrement) external onlyCOO whenNotFrozen {
        _setMinimumPriceIncrement(_newMinimumPriceIncrement);
        emit MinimumPriceIncrementUpdated(_newMinimumPriceIncrement);
    }

    /// @notice Utility function used internally for the setMinimumTotalValue method.
    /// @notice Given Tmin (_minTotal), flat fee (_unsuccessfulFee),
    ///  Tmin ≥ (2 * flat fee) guarantees that offer prices ≥ flat fee, always. This is important to prevent the
    ///  existence of offers that, when overbid or expired, would result in the main contract taking too big of a cut.
    ///  In the case of a sufficiently low offer price, eg. the same as unsuccessfulFee, the most the main contract can
    ///  ever take is simply the amount of unsuccessfulFee.
    /// @param _newMinTotal The minimumTotalValue value to set.
    /// @param _unsuccessfulFee The unsuccessfulFee value used to check if the _minTotal specified
    ///  is too low.
    function _setMinimumTotalValue(uint256 _newMinTotal, uint256 _unsuccessfulFee) internal {
        require(_newMinTotal >= (2 * _unsuccessfulFee), "minimum value set too low");
        minimumTotalValue = _newMinTotal;
    }

    /// @dev As offerCut is a basis point, the value to set must be less than or equal to 10000.
    /// @param _newOfferCut The offerCut value to set.
    function _setOfferCut(uint256 _newOfferCut) internal {
        require(_newOfferCut <= 1e4, "invalid basis points for offer cut");
        offerCut = _newOfferCut;
    }

    /// @dev As minimumPriceIncrement is a basis point, the value to set must be less than or equal to 10000.
    /// @param _newMinimumPriceIncrement The minimumPriceIncrement value to set.
    function _setMinimumPriceIncrement(uint256 _newMinimumPriceIncrement) internal {
        require(_newMinimumPriceIncrement <= 1e4, "invalid basis points for minimum price increment");
        minimumPriceIncrement = _newMinimumPriceIncrement;
    }
}
