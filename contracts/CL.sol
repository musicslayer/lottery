// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.12 <0.9.0;

import "@chainlink/contracts/src/v0.8/VRFV2WrapperConsumerBase.sol";

// A contract to test Chainlink VRF integration.
// BNB Chain testnet
contract CL is VRFV2WrapperConsumerBase {
    error RandomNumberRequestError();
    error RandomNumberReceiveError();
    error RandomNumberUseError();

    event RandomNumberRequested();
    event RandomNumberReceived(uint256 indexed requestId, uint256 indexed randomNumber);
    event RandomNumberUsed(uint256 indexed requestId, uint256 indexed randomNumber);

    address constant linkAddress = 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06;
    address constant wrapperAddress = 0x699d428ee890d55D56d5FC6e26290f3247A762bd;

    bool requestIdSet;
    uint256 requestIdBlock;
    uint256 requestId;

    bool randomNumberSet;
    uint256 randomNumber;

    constructor() VRFV2WrapperConsumerBase(linkAddress, wrapperAddress) {}

    /*
    // Callback that will contain the random numbers requested.
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        require(requestId == _requestId, "request not found");
        emit RandomNumber(_requestId, _randomWords[0]);
    }

    function clTest() external {
        emit RandomNumberPre(77);
        requestId = requestRandomness(callbackGasLimit, requestConfirmations, numWords);
    }
    */

    // Get this contract's Chainlink balance.
    function getLink() external view returns (uint256) {
        LinkTokenInterface link = LinkTokenInterface(linkAddress);
        return link.balanceOf(address(this));
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        // We want this function to use as little gas as possible, so just validate the requestID and store the random number.
        if(requestId != _requestId) {
            revert RandomNumberReceiveError();
        }

        randomNumberSet = true;
        randomNumber = _randomWords[0];

        emit RandomNumberReceived(_requestId, randomNumber);
    }

    function clTest_requestRandomNumber() external {
        // If we already called this function but  do not have the random number yet, we may try again after a certain number of blocks.
        if(randomNumberSet || (requestIdSet && block.number - requestIdBlock < 400)) { // About 20 minutes
            revert RandomNumberRequestError();
        }

        requestIdSet = true;
        requestIdBlock = block.number;
        requestId = requestRandomness(100, 200, 1);

        emit RandomNumberRequested();
    }

    function clTest_useRandomNumber() external {
        if(!randomNumberSet) {
            revert RandomNumberUseError();
        }

        requestIdSet = false;
        randomNumberSet = false;

        emit RandomNumberUsed(requestId, randomNumber);
    }
}