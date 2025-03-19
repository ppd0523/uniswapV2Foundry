// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;
import "../lib/forge-std/src/Test.sol";
import "../src/UniswapV2Factory.sol";
import "../src/UniswapV2Pair.sol";
import "../src/UniswapV2Router.sol";
import "./mocks/ERC20Mock.sol";
import "./mocks/WETHMock.sol";

contract UniswapV2RouterTest is Test{
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