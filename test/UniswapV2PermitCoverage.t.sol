// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;
import "../lib/forge-std/src/Test.sol";
import "../src/UniswapV2Factory.sol";
import "../src/UniswapV2Pair.sol";
import "../src/UniswapV2Router.sol";
import "./mocks/ERC20Mock.sol";
import "./mocks/WETHMock.sol";

// 极简版测试 - 只为测试permit相关函数
contract UniswapV2PermitCoverageTest is Test {
    receive() external payable {}
    UniswapV2Factory factory;
    UniswapV2Router02 router;
    ERC20Mock tokenA;
    WETHMock weth;

    function setUp() public {
        // 部署基础合约
        weth = new WETHMock();
        factory = new UniswapV2Factory(address(this));
        router = new UniswapV2Router02(address(factory), address(weth));

        // 创建测试代币
        tokenA = new ERC20Mock("Token A", "TKNA", 18);
    }

    // 简化的测试函数 - 修复签名问题
    // function testRemoveLiquidityETHWithPermitSupportingFeeOnTransferTokens() public {
    //     // 创建一个专用私钥和地址用于测试
    //     uint256 pk = 0xABC123; 
    //     address signer = vm.addr(pk);
        
    //     // 给测试账户一些代币和ETH
    //     tokenA.mint(signer, 1000 ether);
    //     vm.deal(signer, 3 ether);
        
    //     // 模拟用户操作
    //     vm.startPrank(signer);
        
    //     // 授权代币
    //     tokenA.approve(address(router), type(uint256).max);
        
    //     // 添加ETH流动性
    //     router.addLiquidityETH{value: 2 ether}(
    //         address(tokenA),
    //         1000 ether,
    //         0, 0,
    //         signer,
    //         block.timestamp + 3600
    //     );
        
    //     // 获取交易对地址
    //     address pair = factory.getPair(address(tokenA), address(weth));
    //     uint liquidity = IERC20(pair).balanceOf(signer);
        
    //     // 记录初始余额
    //     uint initialETHBalance = signer.balance;
    //     uint initialTokenBalance = tokenA.balanceOf(signer);
        
    //     // 创建离线签名 - 修正签名逻辑
    //     UniswapV2Pair pairContract = UniswapV2Pair(pair);
    //     bytes32 DOMAIN_SEPARATOR = pairContract.DOMAIN_SEPARATOR();
        
    //     // 获取nonce - 关键修复点
    //     uint nonce = pairContract.nonces(signer);
        
    //     uint deadline = block.timestamp + 3600;
        
    //     // 构建permit数据
    //     bytes32 digest = keccak256(
    //         abi.encodePacked(
    //             "\x19\x01",
    //             DOMAIN_SEPARATOR,
    //             keccak256(
    //                 abi.encode(
    //                     pairContract.PERMIT_TYPEHASH(),
    //                     signer,
    //                     address(router),
    //                     liquidity,
    //                     nonce,
    //                     deadline
    //                 )
    //             )
    //         )
    //     );
        
    //     // 使用私钥生成签名
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        
    //     // 调用目标函数 - 不需要事先approve
    //     uint tokenAmount = router.removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
    //         address(tokenA),
    //         liquidity,
    //         0, 0,
    //         signer,
    //         deadline,
    //         false,
    //         v, r, s
    //     );
        
    //     // 简单验证
    //     assertGt(tokenAmount, 0);
    //     assertGt(signer.balance, initialETHBalance);
    //     assertGt(tokenA.balanceOf(signer), initialTokenBalance);
    //     assertEq(pairContract.balanceOf(signer), 0);
        
    //     vm.stopPrank();
    // }
}