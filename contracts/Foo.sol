// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.12 <0.9.0;

contract Foo {
    function foo(uint input) external pure returns (uint) {
        return input * input;
    }
}