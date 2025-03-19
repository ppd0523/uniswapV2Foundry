// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../lib/forge-std/src/Test.sol";
import "../src/UniswapV2Pair.sol";

contract GetInitCodeHashTest is Test {
    function testGetInitCodeHash() public {
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 hash = keccak256(abi.encodePacked(bytecode));
        console.logBytes32(hash);
    }
}