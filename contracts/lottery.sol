// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

/**
 * @title Lottery
 * @dev A blockchain lottery
 * @custom:dev-run-script ./scripts/deploy_with_ethers.ts
 */
contract Lottery {
    mapping(address => bool) public map_isPlaying;

    function registerAddress(address payable playerAddress) public {
        // If address is already playing, we need to error. An address can only enter the lottery once.
        bool isPlaying = map_isPlaying[playerAddress];
        require(!isPlaying, "This address has already entered the lottery.");

        // Register this address as a player in the lottery.
        map_isPlaying[playerAddress] = true;
    }
    
    function isAddressPlaying(address payable playerAddress) public view returns (bool) {
        //map_isPlaying[playerAddress] = true;
        return map_isPlaying[playerAddress];
    }
}