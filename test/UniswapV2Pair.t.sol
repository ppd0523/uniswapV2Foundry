// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../lib/forge-std/src/Test.sol";
import "../src/UniswapV2Pair.sol";
import "../src/UniswapV2Factory.sol";
import "./mocks/ERC20Mock.sol";

contract UniswapV2PairTest is Test {
    UniswapV2Factory factory;
    UniswapV2Pair pair;
    ERC20Mock tokenA;
    ERC20Mock tokenB;

    address user = address(1);
    address feeToSetter = address(2);
    address feeTo = address(3);

    // 测试所需的初始代币数量
    uint constant INITIAL_AMOUNT = 100000 ether;

    function setUp() public {
        // 部署代币和工厂合约
        factory = new UniswapV2Factory(feeToSetter);

        tokenA = new ERC20Mock("Token A", "TKNA", 18);
        tokenB = new ERC20Mock("Token B", "TKNB", 18);

        // 确保 tokenA 地址小于 tokenB 地址
        if (address(tokenA) > address(tokenB)) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }

        // 创建交易对
        factory.createPair(address(tokenA), address(tokenB));
        pair = UniswapV2Pair(factory.getPair(address(tokenA), address(tokenB)));

        // 铸造代币用于测试
        tokenA.mint(address(this), INITIAL_AMOUNT);
        tokenB.mint(address(this), INITIAL_AMOUNT);
        tokenA.mint(user, INITIAL_AMOUNT);
        tokenB.mint(user, INITIAL_AMOUNT);
    }

    // 测试 initialize 函数
    function testInitialize() public {
        assertEq(pair.token0(), address(tokenA));
        assertEq(pair.token1(), address(tokenB));
        assertEq(pair.factory(), address(factory));

        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 0);
    }

    // 测试首次添加流动性
    function testMintInitial() public {
        uint amount0 = 1000 ether;
        uint amount1 = 4000 ether;

        // 转账代币到交易对
        tokenA.transfer(address(pair), amount0);
        tokenB.transfer(address(pair), amount1);

        // 调用mint添加流动性
        uint liquidity = pair.mint(address(this));

        // 验证流动性计算
        uint expectedLiquidity = sqrt(amount0 * amount1) - 1000; // 减去MINIMUM_LIQUIDITY
        assertEq(liquidity, expectedLiquidity);

        // 验证储备金更新
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertEq(reserve0, amount0);
        assertEq(reserve1, amount1);

        // 验证LP代币余额
        assertEq(pair.balanceOf(address(this)), expectedLiquidity);
        assertEq(pair.balanceOf(address(0)), 1000); // MINIMUM_LIQUIDITY锁定
    }

    // 测试向已有流动性的池子添加更多流动性
    function testMintExisting() public {
        // 首先添加初始流动性
        tokenA.transfer(address(pair), 1000 ether);
        tokenB.transfer(address(pair), 4000 ether);
        pair.mint(address(this));

        uint initialLiquidity = pair.balanceOf(address(this));

        // 再添加一半的流动性
        uint amount0 = 500 ether;
        uint amount1 = 2000 ether;
        tokenA.transfer(address(pair), amount0);
        tokenB.transfer(address(pair), amount1);

        uint newLiquidity = pair.mint(address(this));

        // 验证新流动性 (应该是初始流动性的一半)
        assertApproxEqRel(newLiquidity, initialLiquidity / 2, 1e16); // 允许1%误差

        // 验证储备金更新
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertEq(reserve0, 1500 ether);
        assertEq(reserve1, 6000 ether);
    }

    // 测试移除流动性
    function testBurn() public {
        // 添加流动性
        uint amount0 = 1000 ether;
        uint amount1 = 4000 ether;
        tokenA.transfer(address(pair), amount0);
        tokenB.transfer(address(pair), amount1);
        pair.mint(address(this));

        uint liquidity = pair.balanceOf(address(this));

        // 准备移除流动性
        pair.transfer(address(pair), liquidity);

        // 记录移除前的余额
        uint balanceA = tokenA.balanceOf(address(this));
        uint balanceB = tokenB.balanceOf(address(this));

        // 移除流动性
        (uint returnedA, uint returnedB) = pair.burn(address(this));

        // 验证返回金额
        assertApproxEqRel(returnedA, amount0, 1e16); // 因为MINIMUM_LIQUIDITY，会有轻微差异
        assertApproxEqRel(returnedB, amount1, 1e16);

        // 验证代币余额增加
        assertEq(tokenA.balanceOf(address(this)), balanceA + returnedA);
        assertEq(tokenB.balanceOf(address(this)), balanceB + returnedB);

        // 验证LP代币被销毁
        assertEq(pair.balanceOf(address(this)), 0);

        // 验证储备金更新 (保留MINIMUM_LIQUIDITY对应的部分)
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertGt(reserve0, 0);
        assertGt(reserve1, 0);
        assertLt(reserve0, 1 ether); // 极小值
        assertLt(reserve1, 1 ether); // 极小值
    }

    // 测试交换功能 - token0 换 token1
    function testSwapToken0ForToken1() public {
        // 添加流动性
        tokenA.transfer(address(pair), 5000 ether);
        tokenB.transfer(address(pair), 10000 ether);
        pair.mint(address(this));

        uint amount0In = 1000 ether;

        // 计算预期输出 (考虑0.3%手续费)
        uint amountInWithFee = amount0In * 997;
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint expectedOut = (amountInWithFee * uint(reserve1)) /
            (uint(reserve0) * 1000 + amountInWithFee);

        // 转入代币进行交换
        tokenA.transfer(address(pair), amount0In);

        // 执行交换
        pair.swap(0, expectedOut, address(this), new bytes(0));

        // 验证余额变化
        (uint112 newReserve0, uint112 newReserve1, ) = pair.getReserves();
        assertEq(newReserve0, reserve0 + amount0In);
        assertEq(newReserve1, reserve1 - expectedOut);
    }

    // 测试交换功能 - token1 换 token0
    function testSwapToken1ForToken0() public {
        // 添加流动性
        tokenA.transfer(address(pair), 5000 ether);
        tokenB.transfer(address(pair), 10000 ether);
        pair.mint(address(this));

        uint amount1In = 1000 ether;

        // 计算预期输出 (考虑0.3%手续费)
        uint amountInWithFee = amount1In * 997;
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint expectedOut = (amountInWithFee * uint(reserve0)) /
            (uint(reserve1) * 1000 + amountInWithFee);

        // 转入代币进行交换
        tokenB.transfer(address(pair), amount1In);

        // 执行交换
        pair.swap(expectedOut, 0, address(this), new bytes(0));

        // 验证余额变化
        (uint112 newReserve0, uint112 newReserve1, ) = pair.getReserves();
        assertEq(newReserve0, reserve0 - expectedOut);
        assertEq(newReserve1, reserve1 + amount1In);
    }

    // 测试交换失败 - K值减少
    function testSwapFailKValueDecreased() public {
        // 添加流动性
        tokenA.transfer(address(pair), 5000 ether);
        tokenB.transfer(address(pair), 10000 ether);
        pair.mint(address(this));

        uint amount0In = 1000 ether;

        // 计算预期输出
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        // 故意设置过高的输出值，使K值减少
        uint maliciousOutput = (amount0In * uint(reserve1)) / uint(reserve0);

        // 转入代币准备交换
        tokenA.transfer(address(pair), amount0In);

        // 执行交换，应该失败
        vm.expectRevert("UniswapV2: K");
        pair.swap(0, maliciousOutput, address(this), new bytes(0));
    }

    // 测试 sync 函数
    function testSync() public {
        // 直接向交易对转账代币，不通过mint
        tokenA.transfer(address(pair), 1000 ether);
        tokenB.transfer(address(pair), 4000 ether);

        // 验证储备金未更新
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 0);

        // 调用sync更新储备金
        pair.sync();

        // 验证储备金已更新
        (reserve0, reserve1, ) = pair.getReserves();
        assertEq(reserve0, 1000 ether);
        assertEq(reserve1, 4000 ether);
    }

    // 测试 skim 函数
    function testSkim() public {
        // 添加初始流动性
        tokenA.transfer(address(pair), 1000 ether);
        tokenB.transfer(address(pair), 4000 ether);
        pair.mint(address(this));

        // 再次直接转入代币，不调用mint
        tokenA.transfer(address(pair), 500 ether);
        tokenB.transfer(address(pair), 2000 ether);

        // 记录目标接收地址的初始余额
        uint initialBalanceA = tokenA.balanceOf(user);
        uint initialBalanceB = tokenB.balanceOf(user);

        // 调用skim将多余代币转移给user
        pair.skim(user);

        // 验证user余额增加
        assertEq(tokenA.balanceOf(user), initialBalanceA + 500 ether);
        assertEq(tokenB.balanceOf(user), initialBalanceB + 2000 ether);

        // 验证储备金未变化
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertEq(reserve0, 1000 ether);
        assertEq(reserve1, 4000 ether);
    }

    // 测试手续费功能
    function testFeeToMint() public {
        // 设置feeTo地址
        vm.prank(feeToSetter);
        factory.setFeeTo(feeTo);

        // 添加初始流动性
        tokenA.transfer(address(pair), 1000 ether);
        tokenB.transfer(address(pair), 4000 ether);
        pair.mint(address(this));

        // 记录kLast
        uint kLast = pair.kLast();
        assertEq(kLast, 1000 ether * 4000 ether);

        // 执行交换以产生手续费
        tokenA.transfer(address(pair), 100 ether);
        pair.swap(0, 300 ether, address(this), new bytes(0));

        // 再次添加流动性触发手续费分配
        tokenA.transfer(address(pair), 500 ether);
        tokenB.transfer(address(pair), 1700 ether);
        pair.mint(address(this));

        // 验证feeTo地址接收到了LP代币
        uint feeToBalance = pair.balanceOf(feeTo);
        assertGt(feeToBalance, 0);
    }

    // 测试价格累积更新功能
    function testPriceAccumulatorUpdate() public {
        // 1. 添加初始流动性
        uint amount0 = 5000 ether;
        uint amount1 = 10000 ether; // 价格比为 1:2

        tokenA.transfer(address(pair), amount0);
        tokenB.transfer(address(pair), amount1);
        pair.mint(address(this));

        // 2. 检查初始价格累积值
        uint initialPrice0Cumulative = pair.price0CumulativeLast();
        uint initialPrice1Cumulative = pair.price1CumulativeLast();

        // 3. 记录初始储备金和时间戳
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = pair
            .getReserves();
        assertEq(reserve0, amount0);
        assertEq(reserve1, amount1);

        // 4. 前进时间 (以秒为单位)
        uint timeElapsed = 3600; // 前进1小时
        vm.warp(block.timestamp + timeElapsed);

        // 5. 触发价格累积更新
        pair.sync(); // 调用sync强制更新储备和价格累积器

        // 6. 计算预期价格累积增量
        // 使用 UQ112x112 库的逻辑计算价格累积
        // price0 = reserve1/reserve0 = 10000/5000 = 2
        // price1 = reserve0/reserve1 = 5000/10000 = 0.5

        // 在 UQ112x112 中，数字被按 2^112 缩放
        // 在处理时需要考虑这个缩放因子
        uint price0 = (uint(reserve1) << 112) / uint(reserve0); // reserve1/reserve0
        uint price1 = (uint(reserve0) << 112) / uint(reserve1); // reserve0/reserve1

        uint expectedPrice0Increase = price0 * timeElapsed;
        uint expectedPrice1Increase = price1 * timeElapsed;

        // 7. 验证价格累积值是否正确更新
        uint newPrice0Cumulative = pair.price0CumulativeLast();
        uint newPrice1Cumulative = pair.price1CumulativeLast();

        // 检查价格累积增量
        assertEq(
            newPrice0Cumulative - initialPrice0Cumulative,
            expectedPrice0Increase
        );
        assertEq(
            newPrice1Cumulative - initialPrice1Cumulative,
            expectedPrice1Increase
        );

        // 8. 测试多次价格更新
        // 再次前进时间
        vm.warp(block.timestamp + timeElapsed);

        // 执行一次交易改变价格
        // 模拟交换: 添加1000个tokenA，减少大约1667个tokenB
        uint swapAmount = 1000 ether;
        tokenA.transfer(address(pair), swapAmount);

        // 计算等价的tokenB数量 (考虑0.3%手续费)
        uint amountInWithFee = swapAmount * 997;
        uint numerator = amountInWithFee * reserve1;
        uint denominator = reserve0 * 1000 + amountInWithFee;
        uint amountOut = numerator / denominator;

        // 执行交换
        pair.swap(0, amountOut, address(this), new bytes(0));

        // 再次记录价格累积值
        uint midPrice0Cumulative = pair.price0CumulativeLast();
        uint midPrice1Cumulative = pair.price1CumulativeLast();

        // 再前进时间
        vm.warp(block.timestamp + timeElapsed);

        // 再次触发更新
        pair.sync();

        // 验证价格累积再次更新
        uint finalPrice0Cumulative = pair.price0CumulativeLast();
        uint finalPrice1Cumulative = pair.price1CumulativeLast();

        // 确保价格累积继续增加
        assertGt(finalPrice0Cumulative, midPrice0Cumulative);
        assertGt(finalPrice1Cumulative, midPrice1Cumulative);
    }

    // 辅助函数：平方根计算
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
