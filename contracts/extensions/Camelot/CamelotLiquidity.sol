// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../extensions/TransferHelper.sol";
import "../../interfaces/INonfungiblePositionManager.sol";
import "../../interfaces/IERC721Receiver.sol";
import "../../interfaces/IVenderLiquidityProxy.sol";

 struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }
    
contract CamelotLiquidity is IVenderLiquidityProxy, IERC721Receiver {
    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = -MIN_TICK;
    int24 private constant TICK_SPACING = 60;

    INonfungiblePositionManager private nonfungiblePositionManager;
    
    mapping(uint256 => Deposit) public deposits;
    
    constructor(address _nonfungiblePositionManager) {
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
    }

    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    function onERC721Received(
        address operator,
        address from,
        uint tokenId,
        bytes calldata
    ) external returns (bytes4) {
        _createDeposit(operator, tokenId);
        return IERC721Receiver.onERC721Received.selector;
    }

    function _createDeposit(address owner, uint256 tokenId) internal {
        (, , address token0, address token1, , , , uint128 liquidity, , , , ) =
            nonfungiblePositionManager.positions(tokenId);

        deposits[tokenId] = Deposit({
            owner: owner,
            liquidity: liquidity,
            token0: token0,
            token1: token1
        });
    }

    function mintPosition(
        address token0,
        uint256 amount0ToAdd,
        address token1,
        uint256 amount1ToAdd
    ) external returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1) {
        IERC20(token0).approve(address(nonfungiblePositionManager), amount0ToAdd);
        IERC20(token1).approve(address(nonfungiblePositionManager), amount1ToAdd);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: 100,
                tickLower: (MIN_TICK / TICK_SPACING) * TICK_SPACING,
                tickUpper: (MAX_TICK / TICK_SPACING) * TICK_SPACING,
                amount0Desired: amount0ToAdd,
                amount1Desired: amount1ToAdd,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);

        if (amount0 < amount0ToAdd) {
            IERC20(token0).approve(address(nonfungiblePositionManager), 0);
            uint refund0 = amount0ToAdd - amount0;
            IERC20(token1).transfer(msg.sender, refund0);
        }
        if (amount1 < amount1ToAdd) {
            IERC20(token0).approve(address(nonfungiblePositionManager), 0);
            uint refund1 = amount1ToAdd - amount1;
            IERC20(token1).transfer(msg.sender, refund1);
        }
    }

    function collectAllFees(
        uint tokenId
    ) external returns (uint amount0, uint amount1) {
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);
    }

    function increaseLiquidityCurrentRange(
        uint tokenId,
        address token0,
        uint amount0ToAdd,
        address token1,
        uint amount1ToAdd
    ) external returns (uint128 liquidity, uint amount0, uint amount1) {
        IERC20(token0).approve(address(nonfungiblePositionManager), amount0ToAdd);
        IERC20(token1).approve(address(nonfungiblePositionManager), amount1ToAdd);

        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0ToAdd,
                amount1Desired: amount1ToAdd,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (liquidity, amount0, amount1) = nonfungiblePositionManager.increaseLiquidity(params);
    }

    function decreaseLiquidityCurrentRange(
        uint tokenId,
        uint128 liquidity
    ) external returns (uint amount0, uint amount1) {
        INonfungiblePositionManager.DecreaseLiquidityParams
            memory params = INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);
    }

    function rebalancePool(uint256 usdAmount) external pure returns (uint256 ethUsdAmount, uint256 wstEthUsdAmount){
        return (usdAmount/2, usdAmount/2);
    }
}