// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.12 <0.9.0;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol"
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// Chainlink Address: 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06

contract Foo {
    function foo(address tokenContractAddress) external {
        IERC20 tokenContract = IERC20(tokenContractAddress);
        bytes memory callData = abi.encodeWithSelector(tokenContract.transfer.selector, 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4, 0);
        (bool success, bytes memory returnData) = tokenContractAddress.call(callData);
        require(success, "BAD CALL");

        if (returnData.length == 0) {
            require(tokenContractAddress.code.length > 0, "NOT CONTRACT");
        }
    }
}