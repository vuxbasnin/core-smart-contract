// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../../extensions/RockOnyxAccessControl.sol";
import "../../extensions/TransferHelper.sol";
import "../../interfaces/INonfungiblePositionManager.sol";
import "../../interfaces/IVenderLiquidityProxy.sol";
import "hardhat/console.sol";

contract CamelotLiquidity is
    IVenderLiquidityProxy,
    ReentrancyGuard
{
    INonfungiblePositionManager private nonfungiblePositionManager;
    address ethWstEthPoolAddress;

    /************************************************
     *  EVENTS
     ***********************************************/
    event VendorPositionMintted(
        uint256 owner,
        uint128 liquidity,
        uint256 token0,
        uint256 token1
    );

    event VendorPositionIncreased(
        uint256 owner,
        uint128 liquidity,
        uint256 token0,
        uint256 token1
    );

    constructor(address _nonfungiblePositionManager) {
        nonfungiblePositionManager = INonfungiblePositionManager(
            _nonfungiblePositionManager
        );
    }

    function mintPosition(
        int24 lowerTick,
        int24 upperTick,
        address token0,
        uint256 amount0ToAdd,
        address token1,
        uint256 amount1ToAdd
    )
        external
        nonReentrant
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        IERC20(token0).transferFrom(msg.sender, address(this), amount0ToAdd);
        IERC20(token1).transferFrom(msg.sender, address(this), amount1ToAdd);

        IERC20(token0).approve(
            address(nonfungiblePositionManager),
            amount0ToAdd
        );
        IERC20(token1).approve(
            address(nonfungiblePositionManager),
            amount1ToAdd
        );

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                tickLower: lowerTick,
                tickUpper: upperTick,
                amount0Desired: amount0ToAdd,
                amount1Desired: amount1ToAdd,
                amount0Min: 0,
                amount1Min: 0,
                recipient: msg.sender,
                deadline: block.timestamp
            });

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager
            .mint(params);

        if (amount0 < amount0ToAdd) {
            IERC20(token0).approve(address(nonfungiblePositionManager), 0);
            IERC20(token0).transfer(msg.sender, amount0ToAdd - amount0);
        }

        if (amount1 < amount1ToAdd) {
            IERC20(token1).approve(address(nonfungiblePositionManager), 0);
            IERC20(token1).transfer(msg.sender, amount1ToAdd - amount1);
        }

        emit VendorPositionMintted(tokenId, liquidity, amount0, amount1);

        return (tokenId, liquidity, amount0, amount1);
    }

    function increaseLiquidityCurrentRange(
        uint tokenId,
        address token0,
        uint amount0ToAdd,
        address token1,
        uint amount1ToAdd
    )
        external
        nonReentrant
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        require(
            nonfungiblePositionManager.ownerOf(tokenId) == msg.sender,
            "INVALID_TOKENID_OWNER"
        );

        IERC20(token0).transferFrom(msg.sender, address(this), amount0ToAdd);
        IERC20(token1).transferFrom(msg.sender, address(this), amount1ToAdd);

        IERC20(token0).approve(
            address(nonfungiblePositionManager),
            amount0ToAdd
        );
        IERC20(token1).approve(
            address(nonfungiblePositionManager),
            amount1ToAdd
        );

        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: amount0ToAdd,
                    amount1Desired: amount1ToAdd,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

        (liquidity, amount0, amount1) = nonfungiblePositionManager
            .increaseLiquidity(params);

        if (amount0 < amount0ToAdd) {
            IERC20(token0).approve(address(nonfungiblePositionManager), 0);
            IERC20(token0).transfer(msg.sender, amount0ToAdd - amount0);
        }

        if (amount1 < amount1ToAdd) {
            IERC20(token1).approve(address(nonfungiblePositionManager), 0);
            IERC20(token1).transfer(msg.sender, amount1ToAdd - amount1);
        }

        emit VendorPositionIncreased(tokenId, liquidity, amount0, amount1);

        return (liquidity, amount0, amount1);
    }

    function decreaseLiquidityCurrentRange(
        uint256 tokenId,
        uint128 liquidity
    ) external returns (uint256 amount0, uint256 amount1) {
        require(
            nonfungiblePositionManager.ownerOf(tokenId) == msg.sender,
            "INVALID_TOKENID_OWNER"
        );

        INonfungiblePositionManager.DecreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(
            params
        );
    }

    function collectAllFees(
        uint tokenId
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(
            nonfungiblePositionManager.ownerOf(tokenId) == msg.sender,
            "INVALID_TOKENID_OWNER"
        );

        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: msg.sender,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);
    }
}
