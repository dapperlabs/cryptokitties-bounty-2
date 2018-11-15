pragma solidity ^0.4.24;

import "./OffersConfig.sol";

/// @title Base contract for CryptoKitties Offers. Holds all common structs, events, and base variables.
/// @author Dapper Labs Inc. (https://dapperlabs.com)
contract OffersBase is OffersConfig {
    /*** EVENTS ***/

    /// @notice The OfferCreated event is emitted when an offer is created through
    ///  createOffer method.
    /// @param tokenId The token id that a bidder is offering to buy from the owner.
    /// @param expiresAt The timestamp when the offer will be expire.
    /// @param bidder The creator of the offer.
    /// @param total The total eth value the bidder sent to the Offer contract.
    /// @param offerPrice The eth price that the owner of the token will receive
    ///  if the offer is accepted.
    event OfferCreated(
        uint256 tokenId,
        address bidder,
        uint256 expiresAt,
        uint256 total,
        uint256 offerPrice
    );

    /// @notice The OfferCancelled event is emitted when an offer is cancelled before expired.
    /// @param tokenId The token id that the cancelled offer was offering to buy.
    /// @param bidder The creator of the offer.
    /// @param bidderReceived The eth amount that the bidder received as refund.
    /// @param fee The eth amount that CFO received as the fee for the cancellation.
    event OfferCancelled(
        uint256 tokenId,
        address bidder,
        uint256 bidderReceived,
        uint256 fee
    );

    /// @notice The OfferFulfilled event is emitted when an active offer has been fulfilled, meaning
    ///  the bidder now owns the token, and the orignal owner receives the eth amount from the offer.
    /// @param tokenId The token id that the fulfilled offer was offering to buy.
    /// @param owner The original owner of the token who accepted the offer.
    /// @param bidder The creator of the offer.
    /// @param ownerReceived The eth amount that the original owner received from the offer
    /// @param fee The eth amount that CFO received as the fee for the successfully fulfilling.
    event OfferFulfilled(
        uint256 tokenId,
        address bidder,
        address owner,
        uint256 ownerReceived,
        uint256 fee
    );

    /// @notice The OfferUpdated event is emitted when an active offer was either extended the expiry
    ///  or raised the price.
    /// @param tokenId The token id that the updated offer was offering to buy.
    /// @param bidder The creator of the offer, also is whom updated the offer.
    /// @param newExpiresAt The new expiry date of the updated offer.
    /// @param totalRaised The total eth value the bidder sent to the Offer contract to raise the offer.
    ///  if the totalRaised is 0, it means the offer was extended without raising the price.
    event OfferUpdated(
        uint256 tokenId,
        address bidder,
        uint256 newExpiresAt,
        uint256 totalRaised
    );

    /// @notice The ExpiredOfferRemoved event is emitted when an expired offer gets removed. The eth value will
    ///  be returned to the bidder's account, excluding the fee.
    /// @param tokenId The token id that the removed offer was offering to buy
    /// @param bidder The creator of the offer.
    /// @param fee The eth amount that CFO received as the fee.
    event ExpiredOfferRemoved(
      uint256 tokenId,
      address bidder,
      uint256 bidderReceived,
      uint256 fee
    );

    /// @notice The BidderWithdrewFundsWhenFrozen event is emitted when a bidder withdrew their eth value of
    ///  the offer when the contract is frozen.
    /// @param tokenId The token id that withdrawed offer was offering to buy
    /// @param bidder The creator of the offer, also is whom withdrawed the fund.
    /// @param amount The total amount that the bidder received.
    event BidderWithdrewFundsWhenFrozen(
        uint256 tokenId,
        address bidder,
        uint256 amount
    );


    /// @dev The PushFundsFailed event is emitted when the Offer contract fails to send certain amount of eth
    ///  to an address, e.g. sending the fund back to the bidder when the offer was overbidden by a higher offer.
    /// @param tokenId The token id of an offer that the sending fund is involved.
    /// @param to The address that is supposed to receive the fund but failed for any reason.
    /// @param amount The eth amount that the receiver fails to receive.
    event PushFundsFailed(
        uint256 tokenId,
        address to,
        uint256 amount
    );

    /*** DATA TYPES ***/

    /// @dev The Offer struct. The struct fits in two 256-bits words.
    struct Offer {
        // Time when offer expires
        uint64 expiresAt;
        // Bidder The creator of the offer
        address bidder;
        // Offer cut in basis points, which ranges from 0-10000.
        // It's the cut that CFO takes when the offer is successfully accepted by the owner.
        // This is stored in the offer struct so that it won't be changed if COO updates
        // the `offerCut` for new offers.
        uint16 offerCut;
        // Total value (in wei) a bidder sent in msg.value to create the offer
        uint128 total;
        // Fee (in wei) that CFO takes when the offer is expired or overbid.
        // This is stored in the offer struct so that it won't be changed if COO updates
        // the `unsuccessfulFee` for new offers.
        uint128 unsuccessfulFee;
    }

    /*** STORAGE ***/
    /// @notice Mapping from token id to its corresponding offer.
    /// @dev One token can only have one offer.
    ///  Making it public so that solc-0.4.24 will generate code to query offer by a given token id.
    mapping (uint256 => Offer) public tokenIdToOffer;

    /// @notice computes the minimum offer price to overbid a given offer with its offer price.
    ///  The new offer price has to be a certain percentage, which defined by `minimumPriceIncrement`,
    ///  higher than the previous offer price.
    /// @dev This won't overflow, because `_offerPrice` is in uint128, and `minimumPriceIncrement`
    ///  is 16 bits max.
    /// @param _offerPrice The amount of ether in wei as the offer price
    /// @return The minimum amount of ether in wei to overbid the given offer price
    function _computeMinimumOverbidPrice(uint256 _offerPrice) internal view returns (uint256) {
        return (_offerPrice * (1e4 + minimumPriceIncrement)) / 1e4;
    }

    /// @notice Computes the offer price that the owner will receive if the offer is accepted.
    /// @dev This is safe against overflow because msg.value and the total supply of ether is capped within 128 bits.
    /// @param _total The total value of the offer. Also is the msg.value that the bidder sent when
    ///  creating the offer.
    /// @param _offerCut The percentage in basis points that will be taken by the CFO if the offer is fulfilled.
    /// @return The offer price that the owner will receive if the offer is fulfilled.
    function _computeOfferPrice(uint256 _total, uint256 _offerCut) internal pure returns (uint256) {
        return _total * 1e4 / (1e4 + _offerCut);
    }

    /// @notice Check if an offer exists or not by checking the expiresAt field of the offer.
    ///  True if exists, False if not.
    /// @dev Assuming the expiresAt field is from the offer struct in storage.
    /// @dev Since expiry check always come right after the offer existance check, it will save some gas by checking
    /// both existance and expiry on one field, as it only reads from the storage once.
    /// @param _expiresAt The time at which the offer we want to validate expires.
    /// @return True or false (if the offer exists not).
    function _offerExists(uint256 _expiresAt) internal pure returns (bool) {
        return _expiresAt > 0;
    }

    /// @notice Check if an offer is still active by checking the expiresAt field of the offer. True if the offer is,
    ///  still active, False if the offer has expired,
    /// @dev Assuming the expiresAt field is from the offer struct in storage.
    /// @param _expiresAt The time at which the offer we want to validate expires.
    /// @return True or false (if the offer has expired or not).
    function _isOfferActive(uint256 _expiresAt) internal view returns (bool) {
        return now < _expiresAt;
    }

    /// @dev Try pushing the fund to an address.
    /// @notice If sending the fund to the `_to` address fails for whatever reason, then the logic
    ///  will continue and the amount will be kept under the LostAndFound account. Also an event `PushFundsFailed`
    ///  will be emitted for notifying the failure.
    /// @param _tokenId The token id for the offer.
    /// @param _to The address the main contract is attempting to send funds to.
    /// @param _amount The amount of funds (in wei) the main contract is attempting to send.
    function _tryPushFunds(uint256 _tokenId, address _to, uint256 _amount) internal {
        // Sending the amount of eth in wei, and handling the failure.
        // The gas spent transferring funds has a set upper limit
        bool success = _to.send(_amount);
        if (!success) {
            // If failed sending to the `_to` address, then keep the amount under the LostAndFound account by
            // accumulating totalLostAndFoundBalance.
            totalLostAndFoundBalance = totalLostAndFoundBalance + _amount;

            // Emitting the event lost amount.
            emit PushFundsFailed(_tokenId, _to, _amount);
        }
    }
}
