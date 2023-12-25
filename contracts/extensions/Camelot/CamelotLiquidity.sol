// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../../extensions/RockOnyxAccessControl.sol";
import "../../extensions/TransferHelper.sol";
import "../../interfaces/INonfungiblePositionManager.sol";
import "../../interfaces/IERC721Receiver.sol";
import "../../interfaces/IVenderLiquidityProxy.sol";
import "../../interfaces/IUniswapV3Pool.sol";

 struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }
    
contract CamelotLiquidity is IVenderLiquidityProxy, IERC721Receiver, RockOnyxAccessControl, ReentrancyGuard {
    int24 private MIN_TICK_PERCENTAGE;
    int24 private MAX_TICK_PERCENTAGE;
    uint24 private fee;
    INonfungiblePositionManager private nonfungiblePositionManager;
    
    address ethWstEthPoolAddress;
    mapping(uint256 => Deposit) public deposits;
    
    constructor(address _nonfungiblePositionManager, address _ethWstEthPoolAddress, uint24 _fee) {
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        ethWstEthPoolAddress = _ethWstEthPoolAddress;
        fee = _fee;
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
    ) external nonReentrant returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1) {
        (,int24 curTick,,,,,) = IUniswapV3Pool(ethWstEthPoolAddress).slot0();

            int24 lowerTick = curTick - (curTick * MIN_TICK_PERCENTAGE / 100);
            int24 upperTick = curTick + (curTick * MAX_TICK_PERCENTAGE / 100);

        IERC20(token0).transferFrom(msg.sender, address(this), amount0ToAdd);
        IERC20(token1).transferFrom(msg.sender, address(this), amount1ToAdd);

        IERC20(token0).approve(address(nonfungiblePositionManager), amount0ToAdd);
        IERC20(token1).approve(address(nonfungiblePositionManager), amount1ToAdd);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: lowerTick,
                tickUpper: upperTick,
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

        return (tokenId, liquidity, amount0, amount1);
    }

    function collectAllFees(
        uint tokenId
    ) external nonReentrant returns (uint amount0, uint amount1) {
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

    function setTickPercentage(int24 minTick, int24 maxTick) public {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        MIN_TICK_PERCENTAGE = minTick;
        MAX_TICK_PERCENTAGE = maxTick;
    }
}