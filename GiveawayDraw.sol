// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import { VRFCoordinatorV2Interface } from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import { VRFConsumerBaseV2 } from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @author Doggo
 */
contract GiveawayDraw is VRFConsumerBaseV2, Ownable {
	error InvalidInputs();
    error IndexAlreadyUsed();
    error InvalidIndex();
    error NotDrawn();

    event GiveawayCreated(uint256 indexed index);
    event GiveawayWinnerDrawn(uint256 indexed index, address indexed winner);

    struct GiveawayBucket {
        // The winner and the winning amount
        address winner;
        uint96 drawTimestamp;

        // Both indexes are inclusive
        uint80 minIndex;
        uint80 maxIndex;
        uint88 amount;

        // The timestamp where the randomness was fulfilled and the winner was picked
        bool claimed;

        uint256 requestId;
    }

    // Constants

    VRFCoordinatorV2Interface constant VRF_COORDINATOR = VRFCoordinatorV2Interface(0x6168499c0cFfCaCD319c818142124B7A15E857ab);
    bytes32 constant KEY_HASH = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;
    uint16 constant REQUEST_CONFIRMATIONS = 3;
    uint32 constant GAS_LIMIT = 100000;
    uint64 immutable _subscriptionId;

    // Storage Variables

    address[] _giveawayEntries;

    mapping(uint256 => GiveawayBucket) _giveawayBuckets;
    mapping(uint256 => uint256) _requestIdToGiveawayBucketIndex;

    constructor(uint64 subscriptionId) VRFConsumerBaseV2(address(VRF_COORDINATOR)) {
        _subscriptionId = subscriptionId;
    }


    // View only

    function getBucket(uint256 index) public view returns(GiveawayBucket memory) {
        if(_giveawayBuckets[index].requestId == 0) revert InvalidIndex();
        return _giveawayBuckets[index];
    }

    function getWinner(uint256 index) public view returns(address) {
        address winner = getBucket(index).winner;
        if(winner == address(0)) revert NotDrawn();
        return winner;
    }

    function getGiveawayEntry(uint256 index) public view returns(address) {
        return _giveawayEntries[index];
    }


    // Randomness Fulfiller

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        // Get the bucket from storage
        uint256 index = _requestIdToGiveawayBucketIndex[requestId];
        GiveawayBucket storage giveawayBucket = _giveawayBuckets[index];

        // Get a random index that is between the `minIndex` and the `maxIndex` (both inclusive)
        uint256 minIndex = giveawayBucket.minIndex;
        uint256 maxIndex = giveawayBucket.maxIndex;
        uint winnerIndex = (randomWords[0] % (1 + maxIndex - minIndex)) + minIndex;
        address winner = _giveawayEntries[winnerIndex];

        // Set the `winner` and the `drawTimestamp` of the giveaway
        giveawayBucket.winner = winner;
        giveawayBucket.drawTimestamp = uint96(block.timestamp);

        // Emit the event for easy viewing
        emit GiveawayWinnerDrawn(index, winner);
    }

    // Owner Only Methods

    function createGiveawayBucket(uint256 bucketIndex, uint88 giveawayAmount, uint80 minIndex, uint80 maxIndex) external onlyOwner {
        if(_giveawayBuckets[bucketIndex].requestId != 0) revert IndexAlreadyUsed();

        // - the minimum index must be smaller than the maximum index
        // - the maximum index must be a valid entry in the entries array
        // NOTE: This will revert due to an underflow (no error message) if `_giveawayEntries.length == 0`
        //  this behaviour does not cause any issues
        if(maxIndex < minIndex || maxIndex > _giveawayEntries.length - 1) revert InvalidIndex();

        uint256 requestId = VRF_COORDINATOR.requestRandomWords(KEY_HASH, _subscriptionId, REQUEST_CONFIRMATIONS, GAS_LIMIT, 1);

        _requestIdToGiveawayBucketIndex[requestId] = bucketIndex;

        _giveawayBuckets[bucketIndex] = GiveawayBucket({
            winner: address(0),
            amount: giveawayAmount,
            minIndex: minIndex,
            maxIndex: maxIndex,
            drawTimestamp: 0,
            claimed: false,
            requestId: requestId
        });

        emit GiveawayCreated(bucketIndex);
    }


    function pushGiveawayEntries(address[] calldata addresses) external onlyOwner {
        uint len = addresses.length;
        for(uint index = 0; index < len;) {
            unchecked {
                _giveawayEntries.push(addresses[index++]);
            }
        }
    }

    // Backup method in case of a mistake when adding entries using the `pushGiveawayEntries` function
    function replaceGiveawayEntries(uint[] calldata indexes, address[] calldata addresses) external onlyOwner {
        if(indexes.length != addresses.length) revert InvalidInputs();
        uint len = addresses.length;
        for(uint index = 0; index < len;) {
            _giveawayEntries[indexes[index]] = addresses[index];
            unchecked { index++; }
        }
    }

}
