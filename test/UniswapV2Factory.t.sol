// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../lib/forge-std/src/Test.sol";
import "../src/UniswapV2Factory.sol";
import "../src/UniswapV2Pair.sol";
import "./mocks/ERC20Mock.sol";

contract UniswapV2FactoryTest is Test {
    UniswapV2Factory factory;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    address feeToSetter = address(1);

    function setUp() public {
        factory = new UniswapV2Factory(feeToSetter);
        tokenA = new ERC20Mock("Token A", "TKNA", 18);
        tokenB = new ERC20Mock("Token B", "TKNB", 18);
    }

    function testCreatePair() public {
        // 调用createPair函数创建交易对
        address pair = factory.createPair(address(tokenA), address(tokenB));

        // 使用断言验证结果
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.allPairs(0), pair);

        // 验证交易对合约的token0和token1是否正确设置
        UniswapV2Pair pairContract = UniswapV2Pair(pair);
        assertEq(
            pairContract.token0(),
            address(tokenA) < address(tokenB)
                ? address(tokenA)
                : address(tokenB)
        );
        assertEq(
            pairContract.token1(),
            address(tokenA) < address(tokenB)
                ? address(tokenB)
                : address(tokenA)
        );
    }

    function testCannotCreatePairWithSameTokens() public {
        // 使用相同的代币创建交易对，预期会失败
        vm.expectRevert("UniswapV2: IDENTICAL_ADDRESSES");
        factory.createPair(address(tokenA), address(tokenA));
    }

    function testCannotCreatePairWithZeroAddress() public {
        // 使用零地址创建交易对，预期会失败
        vm.expectRevert("UniswapV2: ZERO_ADDRESS");
        factory.createPair(address(0), address(tokenA));
    }

    function testSetFeeTo() public {
        address newFeeTo = address(2);

        // 非授权账户设置feeTo，预期失败
        vm.prank(address(3)); // 模拟由address(3)发起的调用
        vm.expectRevert("UniswapV2: FORBIDDEN");
        factory.setFeeTo(newFeeTo);

        // 授权账户设置feeTo，预期成功
        vm.prank(feeToSetter);
        factory.setFeeTo(newFeeTo);
        assertEq(factory.feeTo(), newFeeTo);
    }
    function testSetFeeToSetter() public {
        address newFeeToSetter = address(4);

        // 非授权账户设置feeToSetter，预期失败
        vm.prank(address(3)); // 模拟由address(3)发起的调用
        vm.expectRevert("UniswapV2: FORBIDDEN");
        factory.setFeeToSetter(newFeeToSetter);

        // 授权账户设置feeToSetter，预期成功
        vm.prank(feeToSetter);
        factory.setFeeToSetter(newFeeToSetter);
        assertEq(factory.feeToSetter(), newFeeToSetter);

        // 验证权限转移成功 - 旧的feeToSetter已无权限
        vm.prank(feeToSetter);
        vm.expectRevert("UniswapV2: FORBIDDEN");
        factory.setFeeToSetter(address(5));

        // 验证新的feeToSetter有权限
        vm.prank(newFeeToSetter);
        factory.setFeeToSetter(address(5));
        assertEq(factory.feeToSetter(), address(5));
    }
}
