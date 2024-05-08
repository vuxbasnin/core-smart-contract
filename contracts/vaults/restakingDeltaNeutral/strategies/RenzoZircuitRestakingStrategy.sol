// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./RestakingStrategy.sol";

contract RenzoZircuitRestakingStrategy is BaseRestakingStrategy {
    
    // restaking vendors
    RenzoRestakingPool private renzoRestakingPool;
    ZircuitRestakingPool private zircuitRestakingPool;

    function ethRestaking_Initialize(
        address _restakingToken,
        address _swapAddress,
        address _usdcAddress,
        address _ethAddress,
        address[] memory _restakingPoolAddresses
    ) internal override {
        // Call the parent method
        super.ethRestaking_Initialize(_restakingToken, _swapAddress, _usdcAddress, _ethAddress, _restakingPoolAddresses);

        renzoRestakingPool = new RenzoRestakingPool(
            _restakingPoolAddresses[0],
            restakingToken
        );
        zircuitRestakingPool = new ZircuitRestakingPool(
            _restakingPoolAddresses[1],
            restakingToken
        );
    }

    function depositToRestakingProxy(uint256 ethAmount) internal override nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        renzoRestakingPool.deposit(ethAmount);

        // get address(this) balanceOf restakingToken
        uint256 restakingTokenBalance = restakingToken.balanceOf(address(this));

        zircuitRestakingPool.deposit(restakingTokenBalance);
    }

    function withdrawFromRestakingProxy(uint256 stakingTokenAmount) internal override nonReentrant {
        
        // Withdraw from zircuit pool
        zircuitRestakingPool.withdraw(stakingTokenAmount);
    }
}