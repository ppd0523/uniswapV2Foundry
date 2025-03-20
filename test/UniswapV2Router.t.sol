// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;
import "../lib/forge-std/src/Test.sol";
import "../src/UniswapV2Factory.sol";
import "../src/UniswapV2Pair.sol";
import "../src/UniswapV2Router.sol";
import "./mocks/ERC20Mock.sol";
import "./mocks/WETHMock.sol";

contract UniswapV2RouterTest is Test {
    UniswapV2Factory factory;
    UniswapV2Router02 router;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
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

        // 确保 tokenA 地址小于 tokenB 地址
        if (address(tokenA) > address(tokenB)) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }

        // address(this) -> test contract address
        // user -> test user address
        // add 100000 tokenA and tokenB to test contract and user
        tokenA.mint(address(this), INITIAL_AMOUNT);
        tokenB.mint(address(this), INITIAL_AMOUNT);
        tokenA.mint(user, INITIAL_AMOUNT);
        tokenB.mint(user, INITIAL_AMOUNT);

        // test contract approve router to transfer tokenA and tokenB
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        // user approve router to transfer tokenA and tokenB
        vm.prank(user);
        tokenA.approve(address(router), type(uint256).max);
        vm.prank(user);
        tokenB.approve(address(router), type(uint256).max);
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

    // Test7: removeLiquidityWithPermit(without prove)
    function testRemoveLiquidityWithPermit() public {
        // 设置测试私钥和对应地址
        uint256 privateKey = 0xA11CE;
        address signer = vm.addr(privateKey);

        // 给测试地址铸造代币
        tokenA.mint(signer, 1000 ether);
        tokenB.mint(signer, 4000 ether);

        // 模拟signer授权代币给路由器
        vm.startPrank(signer);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        // 添加流动性
        (, , uint liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            4000 ether,
            0,
            0,
            signer,
            block.timestamp + 3600
        );

        // 记录初始代币余额
        uint initialBalanceA = tokenA.balanceOf(signer);
        uint initialBalanceB = tokenB.balanceOf(signer);

        // 获取交易对地址
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        uint deadline = block.timestamp + 3600;

        // 获取签名参数
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            pairAddress,
            signer,
            address(router),
            liquidity,
            deadline,
            privateKey
        );

        // 调用removeLiquidityWithPermit
        (uint amountA, uint amountB) = router.removeLiquidityWithPermit(
            address(tokenA),
            address(tokenB),
            liquidity,
            0, // 最小A数量
            0, // 最小B数量
            signer,
            deadline,
            false, // 不使用max approval
            v,
            r,
            s
        );
        vm.stopPrank();

        // 验证结果
        assertApproxEqRel(amountA, 1000 ether, 1e16); // 允许1%误差
        assertApproxEqRel(amountB, 4000 ether, 1e16); // 允许1%误差
        assertEq(tokenA.balanceOf(signer), initialBalanceA + amountA);
        assertEq(tokenB.balanceOf(signer), initialBalanceB + amountB);
        assertEq(UniswapV2Pair(pairAddress).balanceOf(signer), 0);
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
}
