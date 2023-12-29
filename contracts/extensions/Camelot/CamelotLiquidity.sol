// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../../extensions/RockOnyxAccessControl.sol";
import "../../extensions/TransferHelper.sol";
import "../../interfaces/INonfungiblePositionManager.sol";
import "../../interfaces/IERC721Receiver.sol";
import "../../interfaces/IVenderLiquidityProxy.sol";
import "../../interfaces/IVenderPoolState.sol";

contract CamelotLiquidity is IVenderLiquidityProxy, IERC721Receiver, RockOnyxAccessControl, ReentrancyGuard {
    int24 private LOW_TICK_RANGE;
    int24 private UP_TICK_RANGE;
    int24 private TICK_SPACING;
    INonfungiblePositionManager private nonfungiblePositionManager;
    address ethWstEthPoolAddress;
    
    constructor(address _nonfungiblePositionManager, address _ethWstEthPoolAddress) {
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        ethWstEthPoolAddress = _ethWstEthPoolAddress;
        TICK_SPACING = 1;
        LOW_TICK_RANGE = 10;
        LOW_TICK_RANGE = 10;
    }

    function onERC721Received(
        address operator,
        address from,
        uint tokenId,
        bytes calldata
    ) external returns (bytes4) {
    }

    function mintPosition(
        address token0,
        uint256 amount0ToAdd,
        address token1,
        uint256 amount1ToAdd
    ) external nonReentrant payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        //(,int24 curTick,,,,,,) = IVenderPoolState(ethWstEthPoolAddress).globalState();

        // int24 lowerTick = curTick - LOW_TICK_RANGE * TICK_SPACING;
        // int24 upperTick = curTick + UP_TICK_RANGE * TICK_SPACING;

        IERC20(token0).transferFrom(msg.sender, address(this), amount0ToAdd);
        IERC20(token1).transferFrom(msg.sender, address(this), amount1ToAdd);

        IERC20(token0).approve(address(nonfungiblePositionManager), amount0ToAdd);
        IERC20(token1).approve(address(nonfungiblePositionManager), amount1ToAdd);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                tickLower: -88727,
                tickUpper: 887272,
                amount0Desired: amount0ToAdd,
                amount1Desired: amount1ToAdd,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);

        console.log("amount0 "); console.log(amount0);
        console.log("amount1 "); console.log(amount1);
        if (amount0 < amount0ToAdd) {
            IERC20(token0).approve(address(nonfungiblePositionManager), 0);
            IERC20(token0).transfer(msg.sender, amount0ToAdd - amount0);
        }

        if (amount1 < amount1ToAdd) {
            IERC20(token1).approve(address(nonfungiblePositionManager), 0);
            IERC20(token1).transfer(msg.sender, amount1ToAdd - amount1);
        }

        return (tokenId, liquidity, amount0, amount1);
    }

    function collectAllFees(
        address recipient,
        uint tokenId
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: recipient,
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
    ) external nonReentrant returns (uint128 liquidity, uint amount0, uint amount1) {
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

    function setTickRange(int24 lowTickRange, int24 upTickRange) external {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        LOW_TICK_RANGE = lowTickRange;
        UP_TICK_RANGE = upTickRange;
    }
}