pragma solidity ^0.4.24;

import "./ERC721/ERC721Interface.sol";
import "./OffersBase.sol";

/// @title Contract that manages funds from creation to fulfillment for offers made on any ERC-721 token.
/// @author Dapper Labs (https://www.dapperlabs.com)
/// @notice This generic contract interfaces with any ERC-721 compliant contract
contract Offers is OffersBase {

    // This is the main Offers contract. In order to keep our code separated into logical sections,
    // we've broken it up into multiple files using inheritance. This allows us to keep related code
    // collocated while still avoiding a single large file, which would be harder to maintain. The breakdown
    // is as follows:
    //
    //      - OffersBase: This contract defines the fundamental code that the main contract uses.
    //              This includes our main data storage, data types, events, and internal functions for
    //              managing offers in their lifecycle.
    //
    //      - OffersConfig: This contract manages the various configuration values that determine the
    //              details of the offers that get created, cancelled, overbid, expired, and fulfilled,
    //              as well as the fee structure that the offers will be operating with.
    //
    //      - OffersAccessControl: This contract manages the various addresses and constraints for
    //              operations that can be executed only by specific roles. The roles are: CEO, CFO,
    //              COO, and LostAndFound. Additionally, this contract exposes functions for the CFO
    //              to withdraw earnings and the LostAndFound account to withdraw any lost funds.

    /// @dev The ERC-165 interface signature for ERC-721.
    ///  Ref: https://github.com/ethereum/EIPs/issues/165
    ///  Ref: https://github.com/ethereum/EIPs/issues/721
    bytes4 constant InterfaceSignature_ERC721 = bytes4(0x9a20483d);

    // Reference to contract tracking NFT ownership
    ERC721 public nonFungibleContract;

    /// @notice Creates the main Offers smart contract instance and sets initial configuration values
    /// @param _nftAddress The address of the ERC-721 contract managing NFT ownership
    /// @param _globalDuration The initial globalDuration value to set
    /// @param _minimumTotalValue The initial minimumTotalValue value to set
    /// @param _minimumPriceIncrement The initial minimumPriceIncrement value to set
    /// @param _unsuccessfulFee The initial unsuccessfulFee value to set
    /// @param _offerCut The initial offerCut value to set
    constructor(
      address _nftAddress,
      uint256 _globalDuration,
      uint256 _minimumTotalValue,
      uint256 _minimumPriceIncrement,
      uint256 _unsuccessfulFee,
      uint256 _offerCut
    ) public {
        // The creator of the contract is the ceo
        ceoAddress = msg.sender;

        // Get reference of the address of the NFT contract
        ERC721 candidateContract = ERC721(_nftAddress);
        require(candidateContract.supportsInterface(InterfaceSignature_ERC721), "NFT Contract needs to support ERC721 Interface");
        nonFungibleContract = candidateContract;

        // Set initial configuration values
        globalDuration = _globalDuration;
        unsuccessfulFee = _unsuccessfulFee;
        _setOfferCut(_offerCut);
        _setMinimumPriceIncrement(_minimumPriceIncrement);
        _setMinimumTotalValue(_minimumTotalValue, _unsuccessfulFee);
    }

    /// @notice Creates an offer on a token. This contract receives bidders funds and refunds the previous bidder
    ///  if this offer overbids a previously active (unexpired) offer.
    /// @notice When this offer overbids a previously active offer, this offer must have a price greater than
    ///  a certain percentage of the previous offer price, which the minimumOverbidPrice basis point specifies.
    ///  A flat fee is also taken from the previous offer before refund the previous bidder.
    /// @notice When there is a previous offer that has already expired but not yet been removed from storage,
    ///  the new offer can be created with any total value as long as it is greater than the minimumTotalValue.
    /// @notice Works only when contract is not frozen.
    /// @param _tokenId The token a bidder wants to create an offer for
    function createOffer(uint256 _tokenId) external payable whenNotFrozen {
        // T = msg.value
        uint256 total = msg.value;
        // Check that the total amount of the offer isn't below the minimum
        require(total >= minimumTotalValue, "offer total value is below minimum");

        uint256 _offerCut = offerCut;

        // P, the price that owner will see and receive if the offer is accepted.
        uint256 offerPrice = _computeOfferPrice(msg.value, _offerCut);

        Offer storage previousOffer = tokenIdToOffer[_tokenId];
        uint256 previousExpiresAt = previousOffer.expiresAt;

        uint256 toRefund = 0;

        // Check if tokenId already has an offer
        if (_offerExists(previousExpiresAt)) {
            uint256 previousOfferTotal = uint256(previousOffer.total);

            // If the previous offer is still active, the new offer needs to match the previous offer's price
            // plus a minimum required increment (minimumOverbidPrice).
            // We calculate the previous offer's price, the corresponding minimumOverbidPrice, and check if the
            // new offerPrice is greater than or equal to the minimumOverbidPrice
            if (_isOfferActive(previousExpiresAt)) {
                uint256 previousPriceForOwner = _computeOfferPrice(previousOfferTotal, uint256(previousOffer.offerCut));
                uint256 minimumOverbidPrice = _computeMinimumOverbidPrice(previousPriceForOwner);
                require(offerPrice >= minimumOverbidPrice, "overbid price must match minimum price increment criteria");
            }

            uint256 cfoEarnings = previousOffer.unsuccessfulFee;
            // Bidder gets refund: T - flat fee
            toRefund = previousOfferTotal - cfoEarnings;

            totalCFOEarnings += cfoEarnings;
        }

        uint256 newExpiresAt = now + globalDuration;

        // Get a reference of previous bidder address before overwriting with new offer.
        // This is only needed if there is refund
        address previousBidder;
        if (toRefund > 0) {
            previousBidder = previousOffer.bidder;
        }

        tokenIdToOffer[_tokenId] = Offer(
            uint64(newExpiresAt),
            msg.sender,
            uint16(_offerCut),
            uint128(total),
            uint128(unsuccessfulFee)
        );

        // Postpone the refund until the previous offer has been overwritten by the new offer.
        if (toRefund > 0) {
            // Finally, sending funds to this bidder. If failed, the fund will be kept in escrow
            // under lostAndFound's address
            _tryPushFunds(
                _tokenId,
                previousBidder,
                toRefund
            );
        }

        emit OfferCreated(
            _tokenId,
            msg.sender,
            newExpiresAt,
            total,
            offerPrice
        );
    }

    /// @notice Cancels an offer that must exist and be active currently. This moves funds from this contract
    ///  back to the the bidder, after a cut has been taken.
    /// @notice Works only when contract is not frozen.
    /// @param _tokenId The token specified by the offer a bidder wants to cancel
    function cancelOffer(uint256 _tokenId) external whenNotFrozen {
        // Check that offer exists and is active currently
        Offer storage offer = tokenIdToOffer[_tokenId];
        uint256 expiresAt = offer.expiresAt;
        require(_offerExists(expiresAt), "cannot cancel offer that doesn't exist");
        require(_isOfferActive(expiresAt), "cannot cancel offer that has expired");

        address bidder = offer.bidder;
        require(msg.sender == bidder, "cannot cancel offer of another bidder");

        // T
        uint256 total = uint256(offer.total);
        // S
        uint256 offerCut = uint256(offer.offerCut);
        // Bidder gets all of P, CFO gets all of T - P
        uint256 toRefund = _computeOfferPrice(total, offerCut);
        uint256 cfoEarnings = total - toRefund;

        // Remove offer from storage
        delete tokenIdToOffer[_tokenId];

        // Add to CFO's balance
        totalCFOEarnings += cfoEarnings;

        // Transfer money in escrow back to bidder
        _tryPushFunds(_tokenId, bidder, toRefund);

        emit OfferCancelled(
            _tokenId,
            bidder,
            toRefund,
            cfoEarnings
        );
    }

    /// @notice Fulfills an offer that must exist and be active currently. This moves the funds of the
    ///  offer held in escrow in this contract to the owner of the token, and atomically transfers the
    ///  token from the owner to the bidder. A cut is taken by this contract.
    /// @notice We also acknowledge the possible difficulties of keeping in-sync with the Ethereum
    ///  blockchain, and have allowed for fulfilling offers by specifying the _minOfferPrice at which the owner
    ///  of the token is happy to accept the offer. Thus, the owner will always receive the latest offer
    ///  price, which can only be at least the _minOfferPrice that was specified. Specifically, this
    ///  implementation is designed to prevent the edge case where the owner accidentally accepts an offer
    ///  with a price lower than intended. For example, this can happen when the owner fulfills the offer
    ///  precisely when the offer expires and is subsequently replaced with a new offer priced lower.
    /// @notice Works only when contract is not frozen.
    /// @dev We make sure that the token is not on auction when we fulfill an offer, because the owner of the
    ///  token would be the auction contract instead of the user. This function requires that this Offers contract
    ///  is approved for the token in order to make the call to transfer token ownership. This is sufficient
    ///  because approvals are cleared on transfer (including transfer to the auction).
    /// @param _tokenId The token specified by the offer that will be fulfilled.
    /// @param _minOfferPrice The minimum price at which the owner of the token is happy to accept the offer.
    function fulfillOffer(uint256 _tokenId, uint128 _minOfferPrice) external whenNotFrozen {
        // Check that offer exists and is active currently
        Offer storage offer = tokenIdToOffer[_tokenId];
        uint256 expiresAt = offer.expiresAt;
        require(_offerExists(expiresAt), "cannot fulfill offer that doesn't exist");
        require(_isOfferActive(expiresAt), "cannot fulfill expired offer!");

        // Get the owner of the token
        address owner = nonFungibleContract.ownerOf(_tokenId);

        require(msg.sender == cooAddress || msg.sender == owner, "only COO or the owner can fulfill order");

        // T
        uint256 total = uint256(offer.total);
        // S
        uint256 offerCut = uint256(offer.offerCut);
        // P
        uint256 offerPrice = _computeOfferPrice(total, offerCut);

        // Check if the offer price is below the minimum that the owner is happy to accept the offer for
        require(offerPrice >= _minOfferPrice, "cannot fufill offer – offer price too low");

        // Get a reference of the bidder address before removing offer from storage
        address bidder = offer.bidder;

        // Remove offer from storage
        delete tokenIdToOffer[_tokenId];

        // Transfer token on behalf of owner to bidder
        nonFungibleContract.transferFrom(owner, bidder, _tokenId);

        // NFT has been transferred! Now calculate fees and transfer fund to the owner
        // T - P, the CFO's earnings
        uint256 cfoEarnings = total - offerPrice;
        totalCFOEarnings += cfoEarnings;

        // Transfer money in escrow to owner
        _tryPushFunds(_tokenId, owner, offerPrice);

        emit OfferFulfilled(
            _tokenId,
            bidder,
            owner,
            offerPrice,
            cfoEarnings
        );
    }

    /// @notice Removes any existing and inactive (expired) offers from storage. In doing so, this contract
    ///  takes a flat fee from the total amount attached to each offer before sending the remaining funds
    ///  back to the bidder.
    /// @notice Nothing will be done if the offer for a token is either non-existent or active.
    /// @param _tokenIds The array of tokenIds that will be removed from storage
    function batchRemoveExpired(uint256[] _tokenIds) external whenNotFrozen {
        uint256 len = _tokenIds.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 tokenId = _tokenIds[i];
            Offer storage offer = tokenIdToOffer[tokenId];
            uint256 expiresAt = offer.expiresAt;

            // Skip the offer if not exist
            if (!_offerExists(expiresAt)) {
                continue;
            }
            // Skip if the offer has not expired yet
            if (_isOfferActive(expiresAt)) {
                continue;
            }

            // Get a reference of the bidder address before removing offer from storage
            address bidder = offer.bidder;

            // CFO gets the flat fee
            uint256 cfoEarnings = uint256(offer.unsuccessfulFee);

            // Bidder gets refund: T - flat
            uint256 toRefund = uint256(offer.total) - cfoEarnings;

            // Ensure the previous offer has been removed before refunding
            delete tokenIdToOffer[tokenId];

            // Add to CFO's balance
            totalCFOEarnings += cfoEarnings;

            // Finally, sending funds to this bidder. If failed, the fund will be kept in escrow
            // under lostAndFound's address
            _tryPushFunds(
                tokenId,
                bidder,
                toRefund
            );

            emit ExpiredOfferRemoved(
                tokenId,
                bidder,
                toRefund,
                cfoEarnings
            );
        }
    }

    /// @notice Updates an existing and active offer by setting a new expiration time and, optionally, raise
    ///  the price of the offer.
    /// @notice As the offers are always using the configuration values currently in storage, the updated
    ///  offer may be adhering to configuration values that are different at the time of its original creation.
    /// @dev We check msg.value to determine if the offer price should be raised. If 0, only a new
    ///  expiration time is set.
    /// @param _tokenId The token specified by the offer that will be updated.
    function updateOffer(uint256 _tokenId) external payable whenNotFrozen {
        // Check that offer exists and is active currently
        Offer storage offer = tokenIdToOffer[_tokenId];
        uint256 expiresAt = uint256(offer.expiresAt);
        require(_offerExists(expiresAt), "cannot update offer that doesn't exist");
        require(_isOfferActive(expiresAt), "cannot update offer that has expired!");

        require(msg.sender == offer.bidder, "cannot alter another bidders offer");

        uint256 newExpiresAt = now + globalDuration;

        // Check if the caller wants to raise the offer as well
        if (msg.value > 0) {
            // Set the new price
            offer.total += uint128(msg.value);
        }

        offer.expiresAt = uint64(newExpiresAt);

        emit OfferUpdated(_tokenId, msg.sender, newExpiresAt, msg.value);

    }

    /// @notice Sends funds of each existing offer held in escrow back to bidders. The function is callable
    ///  by anyone.
    /// @notice Works only when contract is frozen. In this case, we want to allow all funds to be returned
    ///  without taking any fees.
    /// @param _tokenId The token specified by the offer a bidder wants to withdraw funds for.
    function bidderWithdrawFunds(uint256 _tokenId) external whenFrozen {
        // Check that offer exists
        Offer storage offer = tokenIdToOffer[_tokenId];
        uint256 expiresAt = offer.expiresAt;
        require(_offerExists(expiresAt), "offer doesn't exist for such token id");
        require(msg.sender == offer.bidder, "only bidders can withdraw their funds in escrow");

        // Get a reference of the total to withdraw before removing offer from storage
        uint256 total = uint256(offer.total);

        delete tokenIdToOffer[_tokenId];

        // Send funds back to bidders!
        msg.sender.transfer(total);

        emit BidderWithdrewFundsWhenFrozen(_tokenId, msg.sender, total);
    }

    /// @notice we don't accept any value transfer.
    function() external payable {
        revert("we don't accept any payments!");
    }
}
