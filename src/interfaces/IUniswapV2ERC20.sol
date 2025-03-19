// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./IERC20.sol";

interface IUniswapV2ERC20 is IERC20 {
    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);
    function permit( address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s ) external;
}