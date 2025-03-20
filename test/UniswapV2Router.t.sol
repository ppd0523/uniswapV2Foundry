// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;
import "../lib/forge-std/src/Test.sol";
import "../src/UniswapV2Factory.sol";
import "../src/UniswapV2Pair.sol";
import "../src/UniswapV2Router.sol";
import "./mocks/ERC20Mock.sol";
import "./mocks/WETHMock.sol";

contract UniswapV2RouterTest is Test {
    receive() external payable {}
    UniswapV2Factory factory;
    UniswapV2Router02 router;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    ERC20Mock tokenC;
    WETHMock weth;

    address user = address(1);
    address feeToSetter = address(2);

    // 测试所需的初始代币数量
    uint constant INITIAL_AMOUNT = 100000 ether;

    function setUp() public {
        // 部署合约
        weth = new WETHMock();
        factory = new UniswapV2Factory(feeToSetter);
        router = new UniswapV2Router02(address(factory), address(weth));

        // 创建测试代币
        tokenA = new ERC20Mock("Token A", "TKNA", 18);
        tokenB = new ERC20Mock("Token B", "TKNB", 18);
        tokenC = new ERC20Mock("Token C", "TKNC", 18);

        // 确保 tokenA 地址小于 tokenB 地址
        if (address(tokenA) > address(tokenB)) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }

        // address(this) -> test contract address
        // user -> test user address
        // add 100000 tokenA and tokenB to test contract and user
        tokenA.mint(address(this), INITIAL_AMOUNT);
        tokenB.mint(address(this), INITIAL_AMOUNT);
        tokenC.mint(address(this), INITIAL_AMOUNT); // 给 tokenC 铸造代币
        tokenA.mint(user, INITIAL_AMOUNT);
        tokenB.mint(user, INITIAL_AMOUNT);
        tokenC.mint(user, INITIAL_AMOUNT); // 给用户铸造 tokenC

        // 授权
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        tokenC.approve(address(router), type(uint256).max); // 授权 tokenC
        // user approve router to transfer tokenA and tokenB
        vm.prank(user);
        tokenA.approve(address(router), type(uint256).max);
        vm.prank(user);
        tokenB.approve(address(router), type(uint256).max);
        vm.prank(user);
        tokenC.approve(address(router), type(uint256).max);
    }

    // Test1: first add liquidity
    function testAddLiquidityInitial() public {
        uint amountADesired = 1000 ether;
        uint amountBDesired = 4000 ether;

        // 添加流动性
        (uint amountA, uint amountB, uint liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountADesired,
            amountBDesired,
            0, // amountAMin
            0, // amountBMin
            address(this),
            block.timestamp + 3600 // deadline
        );

        // 验证使用了全部数量
        assertEq(amountA, amountADesired);
        assertEq(amountB, amountBDesired);

        // 验证LP代币数量 (应该是 sqrt(A*B) - MINIMUM_LIQUIDITY)
        // 1000 LP will send to address(0) when first add liquidity
        uint expectedLiquidity = sqrt(amountA * amountB) - 1000; // MINIMUM_LIQUIDITY = 1000
        assertEq(liquidity, expectedLiquidity);

        // 获取交易对地址和合约
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);

        // 验证储备量
        // shoulde be 1000 A and 4000 B
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertEq(reserve0, amountA);
        assertEq(reserve1, amountB);

        // 验证LP代币余额
        assertEq(pair.balanceOf(address(this)), liquidity);
    }

    // 测试 addLiquidity 函数的 else 分支 - 当 amountBOptimal > amountBDesired 时
    // 修复流动性计算公式
    function testAddLiquidityOptimalACalculation() public {
        // 首先添加初始流动性，设置一个具体的比例，比如 A:B = 2:1
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            500 ether,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 获取交易对地址
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));

        // 记录初始代币余额
        uint initialBalanceA = tokenA.balanceOf(address(this));
        uint initialBalanceB = tokenB.balanceOf(address(this));

        // 现在尝试添加的数量 - 触发 else 分支
        uint amountADesired = 800 ether;
        uint amountBDesired = 300 ether; // 应当低于 amountBOptimal

        // 添加流动性
        (uint amountA, uint amountB, ) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountADesired,
            amountBDesired,
            0, // amountAMin
            0, // amountBMin
            address(this),
            block.timestamp + 3600
        );

        // 验证结果 - 关键是验证 amountB == amountBDesired 且 amountA < amountADesired
        assertEq(amountB, amountBDesired, "Should use full amount of B");
        assertLt(amountA, amountADesired, "Should use optimal amount of A");

        // 根据比例计算理论上的 amountAOptimal
        uint amountAOptimal = router.quote(
            amountBDesired,
            500 ether,
            1000 ether
        );

        // 验证使用的实际 amountA 等于计算出的 amountAOptimal
        assertEq(
            amountA,
            amountAOptimal,
            "Should use calculated optimal amount of A"
        );

        // 验证代币余额正确扣除
        assertEq(tokenA.balanceOf(address(this)), initialBalanceA - amountA);
        assertEq(tokenB.balanceOf(address(this)), initialBalanceB - amountB);
    }

    // Test2: add liquidity to existing pair
    function testAddLiquidityExisting() public {
        // 首先添加初始流动性
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            4000 ether,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 记录初始余额
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);
        uint initialLPBalance = pair.balanceOf(address(this));

        // add more liquidity with same ratio
        uint amountADesired = 500 ether;
        uint amountBDesired = 2000 ether;

        (uint amountA, uint amountB, uint liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountADesired,
            amountBDesired,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 验证使用了全部期望数量
        assertEq(amountA, amountADesired);
        assertEq(amountB, amountBDesired);

        // 验证新的LP代币数量
        // half of initial LP
        // cuz first: (1000, 4000), second: (500, 2000)
        uint expectedLPIncrease = initialLPBalance / 2; // 增加50%
        assertApproxEqRel(liquidity, expectedLPIncrease, 1e16); // 允许1%误差

        // 验证新的储备量
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertEq(reserve0, 1000 ether + amountA);
        assertEq(reserve1, 4000 ether + amountB);
    }

    // Test3: remove liquidity
    function testRemoveLiquidity() public {
        // 首先添加流动性
        (, , uint liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            4000 ether,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 记录初始代币余额
        uint initialBalanceA = tokenA.balanceOf(address(this));
        uint initialBalanceB = tokenB.balanceOf(address(this));

        // 获取交易对地址
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);

        // approve router to transfer LP
        pair.approve(address(router), type(uint256).max);

        // remove all liquidity
        (uint amountA, uint amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 验证移除的代币数量接近原始数量 (会少一些因为MINIMUM_LIQUIDITY)
        assertApproxEqRel(amountA, 1000 ether, 1e16);
        assertApproxEqRel(amountB, 4000 ether, 1e16);

        // check tokenA&B have been transfered to test contract
        assertEq(tokenA.balanceOf(address(this)), initialBalanceA + amountA);
        assertEq(tokenB.balanceOf(address(this)), initialBalanceB + amountB);

        // check LP token have been removed
        assertEq(pair.balanceOf(address(this)), 0);
    }

    // Test4: swap token( exactTokensForTokens )
    function testSwapExactTokensForTokens() public {
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            4000 ether,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 记录初始余额
        uint initialBalanceB = tokenB.balanceOf(address(this));

        // 构建路径数组
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // 交换精确数量的代币
        uint amountIn = 10 ether;
        uint amountOutMin = 30 ether; // 期望至少获得30 tokenB

        uint[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 3600
        );
        // 验证输入和输出数量
        assertEq(amounts[0], amountIn); // 输入金额
        assertGt(amounts[1], amountOutMin); // 输出金额 > 最小期望值

        // 验证实际收到了代币
        assertEq(tokenB.balanceOf(address(this)), initialBalanceB + amounts[1]);

        // 获取交易对并检查新的储备量
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        // 验证储备量更新: A增加，B减少
        assertEq(reserve0, 1000 ether + amountIn);
        assertEq(reserve1, 4000 ether - amounts[1]);
    }

    // Test5: add liquidity with ETH
    function testAddLiquidityETH() public {
        uint tokenAmount = 1000 ether;
        uint ethAmount = 2 ether;

        // 添加ETH流动性
        (uint amountToken, uint amountETH, uint liquidity) = router
            .addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 验证使用了全部指定数量
        assertEq(amountToken, tokenAmount);
        assertEq(amountETH, ethAmount);

        // 验证LP代币数量
        uint expectedLiquidity = sqrt(amountToken * amountETH) - 1000; // WETH有18位小数
        assertApproxEqRel(liquidity, expectedLiquidity, 1e16); // 允许1%误差

        // 获取交易对地址
        address pairAddress = factory.getPair(address(tokenA), address(weth));
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);

        // 验证储备量
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        // 确保与排序顺序一致
        if (address(tokenA) < address(weth)) {
            assertEq(reserve0, amountToken);
            assertEq(reserve1, amountETH);
        } else {
            assertEq(reserve0, amountETH);
            assertEq(reserve1, amountToken);
        }

        // 验证LP代币余额
        assertEq(pair.balanceOf(address(this)), liquidity);
    }

    // Test6: minimum amount out
    function testAddLiquidityWithMinimumAmounts() public {
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            4000 ether,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );
        // 尝试以不同比例添加，但设置最小值过高
        uint amountADesired = 500 ether;
        uint amountBDesired = 2500 ether; // 比例为1:5，实际会用1:4
        uint amountBMin = 2200 ether; // 超过了会实际使用的2000 ether
        vm.expectRevert("UniswapV2Router: INSUFFICIENT_B_AMOUNT");
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountADesired,
            amountBDesired,
            0,
            amountBMin,
            address(this),
            block.timestamp + 3600
        );
    }

    // 测试从ETH流动性池移除流动性
    function testRemoveLiquidityETH() public {
        // 设置初始金额
        uint tokenAmount = 1000 ether;
        uint ethAmount = 2 ether;

        // 添加ETH流动性
        router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 获取LP代币地址和数量
        address pair = factory.getPair(address(tokenA), address(weth));
        uint liquidity = IERC20(pair).balanceOf(address(this));

        // 授权路由器使用LP代币
        IERC20(pair).approve(address(router), liquidity);

        // 记录初始余额
        uint initialTokenBalance = tokenA.balanceOf(address(this));
        uint initialETHBalance = address(this).balance;

        // 移除流动性
        (uint amountToken, uint amountETH) = router.removeLiquidityETH(
            address(tokenA),
            liquidity,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 验证返回的代币和ETH数量
        assertGt(amountToken, 0, "Should return tokens");
        assertGt(amountETH, 0, "Should return ETH");

        // 验证余额变化
        assertEq(
            tokenA.balanceOf(address(this)),
            initialTokenBalance + amountToken
        );
        assertEq(address(this).balance, initialETHBalance + amountETH);

        // 验证LP代币已被销毁
        assertEq(IERC20(pair).balanceOf(address(this)), 0);
    }

    // 添加此简化版测试函数，专为覆盖率测试使用
    function testRemoveLiquidityWithPermitSimplified() public {
        // 设置测试私钥和对应地址
        uint256 privateKey = 0xA11CE;
        address signer = vm.addr(privateKey);

        // 添加流动性的准备工作
        tokenA.mint(signer, 1000 ether);
        tokenB.mint(signer, 4000 ether);

        vm.startPrank(signer);

        // 批准代币转移
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        // 添加流动性
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            4000 ether,
            0,
            0,
            signer,
            block.timestamp + 3600
        );

        // 获取必要信息
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);
        uint liquidity = pair.balanceOf(signer);

        // ======= 减少变量，简化流程 =======

        // 生成签名 - 使用更少的局部变量
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                pair.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        pair.PERMIT_TYPEHASH(),
                        signer,
                        address(router),
                        liquidity,
                        pair.nonces(signer),
                        block.timestamp + 3600
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // 使用permit移除流动性
        router.removeLiquidityWithPermit(
            address(tokenA),
            address(tokenB),
            liquidity,
            0,
            0,
            signer,
            block.timestamp + 3600,
            false,
            v,
            r,
            s
        );

        // 简化验证: 只验证LP代币被销毁
        assertEq(pair.balanceOf(signer), 0);
        vm.stopPrank();
    }

    // 测试使用permit移除ETH流动性
    // function testRemoveLiquidityETHWithPermitSimplified() public {
    //     // 设置测试私钥和对应地址
    //     uint256 privateKey = 0xB22CE; // 使用不同的私钥避免nonce冲突
    //     address signer = vm.addr(privateKey);

    //     // 铸造代币给测试地址
    //     tokenA.mint(signer, 1000 ether);

    //     // 给signer一些ETH
    //     vm.deal(signer, 3 ether);

    //     vm.startPrank(signer);

    //     // 授权代币
    //     tokenA.approve(address(router), type(uint256).max);

    //     // 添加ETH流动性
    //     uint ethAmount = 2 ether;
    //     uint tokenAmount = 1000 ether;

    //     (, , uint liquidity) = router.addLiquidityETH{value: ethAmount}(
    //         address(tokenA),
    //         tokenAmount,
    //         0,
    //         0,
    //         signer,
    //         block.timestamp + 3600
    //     );

    //     // 获取交易对地址
    //     address pairAddress = factory.getPair(address(tokenA), address(weth));
    //     UniswapV2Pair pair = UniswapV2Pair(pairAddress);

    //     // 记录初始余额
    //     uint initialTokenBalance = tokenA.balanceOf(signer);
    //     uint initialETHBalance = signer.balance;

    //     // 创建签名
    //     uint deadline = block.timestamp + 3600;
    //     bytes32 digest = keccak256(
    //         abi.encodePacked(
    //             "\x19\x01",
    //             pair.DOMAIN_SEPARATOR(),
    //             keccak256(
    //                 abi.encode(
    //                     pair.PERMIT_TYPEHASH(),
    //                     signer,
    //                     address(router),
    //                     liquidity,
    //                     pair.nonces(signer),
    //                     deadline
    //                 )
    //             )
    //         )
    //     );

    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

    //     // 使用permit移除ETH流动性
    //     (uint returnedToken, uint returnedETH) = router
    //         .removeLiquidityETHWithPermit(
    //             address(tokenA),
    //             liquidity,
    //             0,
    //             0,
    //             signer,
    //             deadline,
    //             false, // 不使用最大值
    //             v,
    //             r,
    //             s
    //         );

    //     // 简化验证
    //     assertEq(pair.balanceOf(signer), 0, "LP tokens should be burned");
    //     assertGt(returnedToken, 0, "Should return tokens");
    //     assertGt(returnedETH, 0, "Should return ETH");
    //     assertEq(
    //         tokenA.balanceOf(signer),
    //         initialTokenBalance + returnedToken,
    //         "Token balance should increase"
    //     );
    //     assertEq(
    //         signer.balance,
    //         initialETHBalance + returnedETH,
    //         "ETH balance should increase"
    //     );

    //     vm.stopPrank();
    // }

    // 测试从ETH流动性池移除支持转账费用的代币
    function testRemoveLiquidityETHSupportingFeeOnTransferTokens() public {
        // 设置初始金额
        uint tokenAmount = 1000 ether;
        uint ethAmount = 2 ether;

        // 添加ETH流动性
        router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 获取LP代币地址和数量
        address pair = factory.getPair(address(tokenA), address(weth));
        uint liquidity = IERC20(pair).balanceOf(address(this));

        // 授权路由器使用LP代币
        IERC20(pair).approve(address(router), liquidity);

        // 记录初始余额
        uint initialTokenBalance = tokenA.balanceOf(address(this));
        uint initialETHBalance = address(this).balance;

        // 移除流动性，使用支持转账费用的函数
        uint amountToken = router
            .removeLiquidityETHSupportingFeeOnTransferTokens(
                address(tokenA),
                liquidity,
                0,
                0,
                address(this),
                block.timestamp + 3600
            );

        // 验证结果
        assertGt(amountToken, 0, "Should return tokens");

        // 验证ETH余额增加
        assertGt(
            address(this).balance,
            initialETHBalance,
            "ETH balance should increase"
        );

        // 验证LP代币已被销毁
        assertEq(IERC20(pair).balanceOf(address(this)), 0);
    }

    // 测试使用permit移除ETH流动性（支持转账费用代币版本）
    // function testRemoveLiquidityETHWithPermitSupportingFeeOnTransferTokens()
    //     public
    // {
    //     // 设置测试私钥和对应地址
    //     uint256 privateKey = 0xC33CE; // 使用不同的私钥避免nonce冲突
    //     address signer = vm.addr(privateKey);

    //     // 铸造代币给测试地址
    //     tokenA.mint(signer, 1000 ether);

    //     // 给signer一些ETH
    //     vm.deal(signer, 3 ether);

    //     vm.startPrank(signer);

    //     // 授权代币
    //     tokenA.approve(address(router), type(uint256).max);

    //     // 添加ETH流动性
    //     uint ethAmount = 2 ether;
    //     uint tokenAmount = 1000 ether;

    //     (, , uint liquidity) = router.addLiquidityETH{value: ethAmount}(
    //         address(tokenA),
    //         tokenAmount,
    //         0,
    //         0,
    //         signer,
    //         block.timestamp + 3600
    //     );

    //     // 获取交易对地址
    //     address pairAddress = factory.getPair(address(tokenA), address(weth));
    //     UniswapV2Pair pair = UniswapV2Pair(pairAddress);

    //     // 记录初始余额
    //     uint initialTokenBalance = tokenA.balanceOf(signer);
    //     uint initialETHBalance = signer.balance;

    //     // 创建签名
    //     uint deadline = block.timestamp + 3600;
    //     bytes32 digest = keccak256(
    //         abi.encodePacked(
    //             "\x19\x01",
    //             pair.DOMAIN_SEPARATOR(),
    //             keccak256(
    //                 abi.encode(
    //                     pair.PERMIT_TYPEHASH(),
    //                     signer,
    //                     address(router),
    //                     liquidity,
    //                     pair.nonces(signer),
    //                     deadline
    //                 )
    //             )
    //         )
    //     );

    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

    //     // 使用permit移除ETH流动性（支持转账费用版本）
    //     uint returnedToken = router
    //         .removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
    //             address(tokenA),
    //             liquidity,
    //             0,
    //             0,
    //             signer,
    //             deadline,
    //             false, // 不使用最大值
    //             v,
    //             r,
    //             s
    //         );

    //     // 验证结果
    //     assertEq(pair.balanceOf(signer), 0, "LP tokens should be burned");
    //     assertGt(returnedToken, 0, "Should return tokens");

    //     // 验证代币余额增加 - 不检查精确值，只确认增加
    //     assertGt(
    //         tokenA.balanceOf(signer),
    //         initialTokenBalance,
    //         "Token balance should increase"
    //     );

    //     // 验证ETH余额增加 - 不检查精确值，只确认增加
    //     assertGt(
    //         signer.balance,
    //         initialETHBalance,
    //         "ETH balance should increase"
    //     );

    //     vm.stopPrank();
    // }
    // 测试使用permit移除ETH流动性（支持转账费用代币版本）- 优化版

    // 测试 swapTokensForExactTokens 功能
    function testSwapTokensForExactTokens() public {
        // 添加流动性
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            4000 ether,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 记录初始余额
        uint initialBalanceA = tokenA.balanceOf(address(this));
        uint initialBalanceB = tokenB.balanceOf(address(this));

        // 构建路径
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // 指定希望获得的确切代币数量
        uint amountOut = 100 ether; // 希望获得100个tokenB
        uint amountInMax = 30 ether; // 最多愿意支付30个tokenA

        // 执行交换
        uint[] memory amounts = router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            address(this),
            block.timestamp + 3600
        );

        // 验证输出和输入金额
        assertEq(
            amounts[1],
            amountOut,
            "Output amount should match requested amount"
        );
        assertLt(
            amounts[0],
            amountInMax,
            "Input amount should be below maximum"
        );

        // 验证实际余额变化
        assertEq(
            tokenB.balanceOf(address(this)),
            initialBalanceB + amountOut,
            "TokenB balance should increase by exact amount"
        );
        assertEq(
            tokenA.balanceOf(address(this)),
            initialBalanceA - amounts[0],
            "TokenA balance should decrease by calculated amount"
        );

        // 验证交易对储备金更新
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        assertEq(
            reserve0,
            1000 ether + amounts[0],
            "Reserve0 should increase by input amount"
        );
        assertEq(
            reserve1,
            4000 ether - amountOut,
            "Reserve1 should decrease by output amount"
        );
    }
    // 测试使用精确数量的代币交换ETH
    function testSwapExactTokensForETH() public {
        // 首先添加ETH/代币流动性
        uint tokenAmount = 1000 ether;
        uint ethAmount = 2 ether;

        router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 记录初始余额
        uint initialTokenBalance = tokenA.balanceOf(address(this));
        uint initialETHBalance = address(this).balance;

        // 构建交易路径
        address[] memory path = new address[](2);
        path[0] = address(tokenA); // 从tokenA开始
        path[1] = address(weth); // 到WETH结束

        // 指定精确的代币输入数量和最小ETH输出
        uint amountTokenIn = 50 ether; // 精确输入50个tokenA
        uint amountETHOutMin = 0.08 ether; // 至少期望获得0.08 ETH

        // 执行交换
        uint[] memory amounts = router.swapExactTokensForETH(
            amountTokenIn,
            amountETHOutMin,
            path,
            address(this),
            block.timestamp + 3600
        );

        // 验证输入金额和输出金额
        assertEq(
            amounts[0],
            amountTokenIn,
            "Input token amount should match exactly"
        );
        assertGe(
            amounts[1],
            amountETHOutMin,
            "Output ETH should be at least the minimum amount"
        );

        // 验证代币余额减少了精确数量
        assertEq(
            tokenA.balanceOf(address(this)),
            initialTokenBalance - amountTokenIn,
            "Token balance should decrease by exact amount"
        );

        // 验证ETH余额增加
        assertEq(
            address(this).balance,
            initialETHBalance + amounts[1],
            "ETH balance should increase by returned amount"
        );

        // 验证交易对储备金更新
        address pairAddress = factory.getPair(address(weth), address(tokenA));
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        // 确保验证顺序正确 (取决于token地址的排序)
        if (address(weth) < address(tokenA)) {
            assertEq(
                reserve1,
                tokenAmount + amountTokenIn,
                "Token reserve should increase"
            );
            assertEq(
                reserve0,
                ethAmount - amounts[1],
                "ETH reserve should decrease"
            );
        } else {
            assertEq(
                reserve0,
                tokenAmount + amountTokenIn,
                "Token reserve should increase"
            );
            assertEq(
                reserve1,
                ethAmount - amounts[1],
                "ETH reserve should decrease"
            );
        }
    }
    // 测试使用精确数量的ETH交换代币
    function testSwapExactETHForTokens() public {
        // 首先添加ETH/代币流动性
        uint tokenAmount = 1000 ether;
        uint ethAmount = 2 ether;

        router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 记录初始余额
        uint initialTokenBalance = tokenA.balanceOf(address(this));
        uint initialETHBalance = address(this).balance;

        // 构建交易路径
        address[] memory path = new address[](2);
        path[0] = address(weth); // 从WETH开始
        path[1] = address(tokenA); // 到tokenA结束

        // 执行交换 - 使用精确数量的ETH
        uint amountETHIn = 0.1 ether;
        uint amountTokenOutMin = 40 ether; // 至少期望得到的代币数量

        uint[] memory amounts = router.swapExactETHForTokens{
            value: amountETHIn
        }(amountTokenOutMin, path, address(this), block.timestamp + 3600);

        // 验证交易结果
        assertEq(amounts[0], amountETHIn, "Input ETH amount should match");
        assertGe(
            amounts[1],
            amountTokenOutMin,
            "Output token amount should be at least the minimum"
        );

        // 验证余额变化
        assertEq(
            address(this).balance,
            initialETHBalance - amountETHIn,
            "ETH balance should decrease"
        );
        assertEq(
            tokenA.balanceOf(address(this)),
            initialTokenBalance + amounts[1],
            "Token balance should increase"
        );

        // 验证交易对储备金更新
        address pairAddress = factory.getPair(address(weth), address(tokenA));
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        // 确保验证顺序正确 (取决于token地址的排序)
        if (address(weth) < address(tokenA)) {
            assertEq(
                reserve0,
                ethAmount + amountETHIn,
                "WETH reserve should increase"
            );
            assertEq(
                reserve1,
                tokenAmount - amounts[1],
                "Token reserve should decrease"
            );
        } else {
            assertEq(
                reserve0,
                tokenAmount - amounts[1],
                "Token reserve should decrease"
            );
            assertEq(
                reserve1,
                ethAmount + amountETHIn,
                "WETH reserve should increase"
            );
        }
    }

    // 测试使用ETH换取确切数量的代币
    function testSwapETHForExactTokens() public {
        // 首先添加ETH/代币流动性
        uint tokenAmount = 1000 ether;
        uint ethAmount = 2 ether;

        router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 记录初始余额
        uint initialTokenBalance = tokenA.balanceOf(address(this));
        uint initialETHBalance = address(this).balance;

        // 构建交易路径
        address[] memory path = new address[](2);
        path[0] = address(weth); // 从WETH开始
        path[1] = address(tokenA); // 到tokenA结束

        // 指定希望获得的确切代币数量和最大ETH输入
        uint amountTokenOut = 50 ether; // 希望获得确切的50个tokenA
        uint amountETHMax = 0.15 ether; // 最多愿意支付0.15 ETH

        // 执行交换，提供足够的ETH以防计算有偏差
        uint[] memory amounts = router.swapETHForExactTokens{
            value: amountETHMax
        }(amountTokenOut, path, address(this), block.timestamp + 3600);

        // 验证获得了确切的代币数量
        assertEq(
            amounts[1],
            amountTokenOut,
            "Should receive exact token amount"
        );

        // 验证花费的ETH不超过最大值
        assertLe(
            amounts[0],
            amountETHMax,
            "ETH spent should not exceed maximum"
        );

        // 验证代币余额增加了确切的数量
        assertEq(
            tokenA.balanceOf(address(this)),
            initialTokenBalance + amountTokenOut,
            "Token balance should increase by exact amount"
        );

        // 验证ETH余额减少了正确的数量
        // 注意：router会退还未使用的ETH
        assertEq(
            address(this).balance,
            initialETHBalance - amounts[0],
            "ETH balance should decrease by calculated amount"
        );

        // 验证交易对储备金更新
        address pairAddress = factory.getPair(address(weth), address(tokenA));
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        // 确保验证顺序正确 (取决于token地址的排序)
        if (address(weth) < address(tokenA)) {
            assertEq(
                reserve0,
                ethAmount + amounts[0],
                "WETH reserve should increase"
            );
            assertEq(
                reserve1,
                tokenAmount - amountTokenOut,
                "Token reserve should decrease"
            );
        } else {
            assertEq(
                reserve0,
                tokenAmount - amountTokenOut,
                "Token reserve should decrease"
            );
            assertEq(
                reserve1,
                ethAmount + amounts[0],
                "WETH reserve should increase"
            );
        }
    }

    // 测试支持收费代币的交换函数
    function testSwapExactTokensForTokensSupportingFeeOnTransferTokens()
        public
    {
        // 添加流动性创建交易对
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            4000 ether,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 记录初始余额
        uint initialBalanceA = tokenA.balanceOf(address(this));
        uint initialBalanceB = tokenB.balanceOf(address(this));

        // 构建交易路径
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // 执行交换 - 使用精确数量的输入代币
        uint amountIn = 10 ether;
        uint amountOutMin = 30 ether; // 至少期望获得的代币数量

        // 调用支持收费代币的交换函数
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 3600
        );

        // 验证输入代币已经从用户余额中扣除
        assertEq(
            tokenA.balanceOf(address(this)),
            initialBalanceA - amountIn,
            "TokenA balance should decrease"
        );

        // 验证输出代币已经添加到用户余额中 - 不检查精确金额，只确认增加了
        assertGt(
            tokenB.balanceOf(address(this)),
            initialBalanceB,
            "TokenB balance should increase"
        );

        // 验证获得的代币数量不少于最小要求
        assertGe(
            tokenB.balanceOf(address(this)) - initialBalanceB,
            amountOutMin,
            "Should receive at least the minimum amount"
        );

        // 验证交易对储备金更新
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        // 确认储备金已更新 - tokenA增加，tokenB减少
        assertEq(
            reserve0,
            1000 ether + amountIn,
            "Reserve0 should increase by exact input amount"
        );
        assertLt(reserve1, 4000 ether, "Reserve1 should decrease");
    }

    // 测试支持转账费用的ETH兑换代币函数
    function testSwapExactETHForTokensSupportingFeeOnTransferTokens() public {
        // 首先添加ETH/代币流动性
        uint tokenAmount = 1000 ether;
        uint ethAmount = 2 ether;

        router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 记录初始余额
        uint initialTokenBalance = tokenA.balanceOf(address(this));
        uint initialETHBalance = address(this).balance;

        // 构建交易路径
        address[] memory path = new address[](2);
        path[0] = address(weth); // 从WETH开始
        path[1] = address(tokenA); // 到tokenA结束

        // 执行交换 - 使用精确数量的ETH
        uint amountETHIn = 0.1 ether;
        uint amountTokenOutMin = 40 ether; // 至少期望得到的代币数量

        // 调用支持费用代币的交换函数
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: amountETHIn
        }(amountTokenOutMin, path, address(this), block.timestamp + 3600);

        // 验证ETH余额减少
        assertEq(
            address(this).balance,
            initialETHBalance - amountETHIn,
            "ETH balance should decrease"
        );

        // 验证代币余额增加 - 不验证精确值，只确认增加了
        assertGt(
            tokenA.balanceOf(address(this)),
            initialTokenBalance,
            "Token balance should increase"
        );

        // 验证获得的代币数量不少于最小要求
        assertGe(
            tokenA.balanceOf(address(this)) - initialTokenBalance,
            amountTokenOutMin,
            "Should receive at least the minimum amount"
        );

        // 验证交易对储备金更新
        address pairAddress = factory.getPair(address(weth), address(tokenA));
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        // 确保验证顺序正确 (取决于token地址的排序)
        if (address(weth) < address(tokenA)) {
            assertEq(
                reserve0,
                ethAmount + amountETHIn,
                "WETH reserve should increase"
            );
            assertLt(reserve1, tokenAmount, "Token reserve should decrease");
        } else {
            assertLt(reserve0, tokenAmount, "Token reserve should decrease");
            assertEq(
                reserve1,
                ethAmount + amountETHIn,
                "WETH reserve should increase"
            );
        }
    }

    // 测试使用代币交换确切数量的ETH
    function testSwapTokensForExactETH() public {
        // 首先添加ETH/代币流动性
        uint tokenAmount = 1000 ether;
        uint ethAmount = 2 ether;

        router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 记录初始余额
        uint initialTokenBalance = tokenA.balanceOf(address(this));
        uint initialETHBalance = address(this).balance;

        // 构建交易路径
        address[] memory path = new address[](2);
        path[0] = address(tokenA); // 从tokenA开始
        path[1] = address(weth); // 到WETH结束

        // 指定希望获得的确切ETH数量和最大代币输入
        uint amountETHOut = 0.1 ether; // 希望获得确切的0.1 ETH
        uint amountTokenInMax = 60 ether; // 最多愿意支付60个tokenA

        // 执行交换
        uint[] memory amounts = router.swapTokensForExactETH(
            amountETHOut,
            amountTokenInMax,
            path,
            address(this),
            block.timestamp + 3600
        );

        // 验证获得了确切的ETH数量
        assertEq(amounts[1], amountETHOut, "Should receive exact ETH amount");

        // 验证花费的代币不超过最大值
        assertLe(
            amounts[0],
            amountTokenInMax,
            "Token spent should not exceed maximum"
        );

        // 验证ETH余额增加了确切的数量
        assertEq(
            address(this).balance,
            initialETHBalance + amountETHOut,
            "ETH balance should increase by exact amount"
        );

        // 验证代币余额减少了正确的数量
        assertEq(
            tokenA.balanceOf(address(this)),
            initialTokenBalance - amounts[0],
            "Token balance should decrease by calculated amount"
        );

        // 验证交易对储备金更新
        address pairAddress = factory.getPair(address(weth), address(tokenA));
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        // 确保验证顺序正确 (取决于token地址的排序)
        if (address(weth) < address(tokenA)) {
            assertEq(
                reserve0,
                ethAmount - amountETHOut,
                "WETH reserve should decrease"
            );
            assertEq(
                reserve1,
                tokenAmount + amounts[0],
                "Token reserve should increase"
            );
        } else {
            assertEq(
                reserve0,
                tokenAmount + amounts[0],
                "Token reserve should increase"
            );
            assertEq(
                reserve1,
                ethAmount - amountETHOut,
                "WETH reserve should decrease"
            );
        }
    }

    // 测试支持转账费用的代币兑换ETH函数
    function testSwapExactTokensForETHSupportingFeeOnTransferTokens() public {
        // 首先添加ETH/代币流动性
        uint tokenAmount = 1000 ether;
        uint ethAmount = 2 ether;

        router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 记录初始余额
        uint initialTokenBalance = tokenA.balanceOf(address(this));
        uint initialETHBalance = address(this).balance;

        // 构建交易路径
        address[] memory path = new address[](2);
        path[0] = address(tokenA); // 从tokenA开始
        path[1] = address(weth); // 到WETH结束

        // 执行交换 - 使用精确数量的代币
        uint amountTokenIn = 50 ether;
        uint amountETHOutMin = 0.08 ether; // 至少期望得到的ETH数量

        // 调用支持费用代币的交换函数
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountTokenIn,
            amountETHOutMin,
            path,
            address(this),
            block.timestamp + 3600
        );

        // 验证代币余额减少
        assertEq(
            tokenA.balanceOf(address(this)),
            initialTokenBalance - amountTokenIn,
            "Token balance should decrease"
        );

        // 验证ETH余额增加 - 不验证精确值，只确认增加了
        assertGt(
            address(this).balance,
            initialETHBalance,
            "ETH balance should increase"
        );

        // 验证获得的ETH数量不少于最小要求
        assertGe(
            address(this).balance - initialETHBalance,
            amountETHOutMin,
            "Should receive at least the minimum ETH amount"
        );

        // 验证交易对储备金更新
        address pairAddress = factory.getPair(address(weth), address(tokenA));
        UniswapV2Pair pair = UniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        // 确保验证顺序正确 (取决于token地址的排序)
        if (address(weth) < address(tokenA)) {
            assertLt(reserve0, ethAmount, "WETH reserve should decrease");
            assertEq(
                reserve1,
                tokenAmount + amountTokenIn,
                "Token reserve should increase"
            );
        } else {
            assertEq(
                reserve0,
                tokenAmount + amountTokenIn,
                "Token reserve should increase"
            );
            assertLt(reserve1, ethAmount, "WETH reserve should decrease");
        }
    }

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

    function _createPermitSignature(
        address pair,
        address owner,
        address spender,
        uint value,
        uint deadline,
        uint256 privateKey
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 DOMAIN_SEPARATOR = UniswapV2Pair(pair).DOMAIN_SEPARATOR();
        bytes32 PERMIT_TYPEHASH = UniswapV2Pair(pair).PERMIT_TYPEHASH();
        uint nonce = UniswapV2Pair(pair).nonces(owner);

        // 计算签名消息哈希 (按照EIP-712标准)
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        spender,
                        value,
                        nonce,
                        deadline
                    )
                )
            )
        );

        // 使用私钥签名消息
        return vm.sign(privateKey, digest);
    }
    // 测试价格计算相关功能
    function testPriceCalculationFunctions() public {
        // 1. 测试 quote 函数 - 计算等值兑换比例
        uint reserveA = 1000 ether;
        uint reserveB = 2000 ether;
        uint amountA = 100 ether;

        // 在比例 1:2 的池中，100个A应该等值于200个B
        uint quotedB = router.quote(amountA, reserveA, reserveB);
        assertEq(quotedB, 200 ether, "Quote calculation error");

        // 2. 测试 getAmountOut 函数 - 考虑手续费的输出计算
        uint amountIn = 100 ether;
        uint reserveIn = 1000 ether;
        uint reserveOut = 2000 ether;

        // 使用公式计算: amountOut = (amountIn * 0.997 * reserveOut) / (reserveIn + amountIn * 0.997)
        uint expectedAmountOut = (amountIn * 997 * reserveOut) /
            (reserveIn * 1000 + amountIn * 997);
        uint calculatedAmountOut = router.getAmountOut(
            amountIn,
            reserveIn,
            reserveOut
        );

        assertEq(
            calculatedAmountOut,
            expectedAmountOut,
            "getAmountOut calculation error"
        );

        // 3. 测试 getAmountIn 函数 - 考虑手续费的输入计算
        uint amountOut = 100 ether;
        reserveIn = 2000 ether;
        reserveOut = 1000 ether;

        // 使用公式计算: amountIn = (reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997) + 1
        uint expectedAmountIn = (reserveIn * amountOut * 1000) /
            ((reserveOut - amountOut) * 997) +
            1;
        uint calculatedAmountIn = router.getAmountIn(
            amountOut,
            reserveIn,
            reserveOut
        );

        assertEq(
            calculatedAmountIn,
            expectedAmountIn,
            "getAmountIn calculation error"
        );

        // 创建实际的流动性池来测试路径计算
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            2000 ether,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 4. 测试 getAmountsOut 函数 - 计算路径上的所有输出金额
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint[] memory amountsOut = router.getAmountsOut(100 ether, path);

        // 检查数组长度
        assertEq(amountsOut.length, 2, "AmountsOut array length should be 2");
        // 检查第一个输入值
        assertEq(
            amountsOut[0],
            100 ether,
            "First amount should be input amount"
        );
        // 检查第二个输出值 (与getAmountOut计算结果一致)
        calculatedAmountOut = router.getAmountOut(
            100 ether,
            1000 ether,
            2000 ether
        );
        assertEq(
            amountsOut[1],
            calculatedAmountOut,
            "Second amount should match getAmountOut result"
        );

        // 5. 测试 getAmountsIn 函数 - 计算路径上的所有输入金额
        uint outputAmount = 100 ether;
        uint[] memory amountsIn = router.getAmountsIn(outputAmount, path);

        // 检查数组长度
        assertEq(amountsIn.length, 2, "AmountsIn array length should be 2");
        // 检查最后一个输出值
        assertEq(
            amountsIn[1],
            outputAmount,
            "Last amount should be output amount"
        );
        // 检查第一个输入值 (与getAmountIn计算结果一致)
        calculatedAmountIn = router.getAmountIn(
            outputAmount,
            1000 ether,
            2000 ether
        );
        assertEq(
            amountsIn[0],
            calculatedAmountIn,
            "First amount should match getAmountIn result"
        );

        // 测试多跳路径计算
        // 先添加另一个流动性池 B-C
        router.addLiquidity(
            address(tokenB),
            address(tokenC),
            2000 ether,
            4000 ether,
            0,
            0,
            address(this),
            block.timestamp + 3600
        );

        // 创建三代币路径 A->B->C
        address[] memory longPath = new address[](3);
        longPath[0] = address(tokenA);
        longPath[1] = address(tokenB);
        longPath[2] = address(tokenC);

        // 测试多跳路径的 getAmountsOut
        uint[] memory longAmountsOut = router.getAmountsOut(
            100 ether,
            longPath
        );
        assertEq(longAmountsOut.length, 3, "Long path should have 3 amounts");
        assertEq(
            longAmountsOut[0],
            100 ether,
            "First input should be 100 ether"
        );

        // 测试多跳路径的 getAmountsIn
        uint[] memory longAmountsIn = router.getAmountsIn(100 ether, longPath);
        assertEq(longAmountsIn.length, 3, "Long path should have 3 amounts");
        assertEq(
            longAmountsIn[2],
            100 ether,
            "Final output should be 100 ether"
        );
    }
}
