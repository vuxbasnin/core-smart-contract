const { expect } = require('chai');
const { ethers, network } = require('hardhat');
import { KelpDaoProxy } from './../../../typechain-types/contracts/vaults/restakingDeltaNeutral/KelpZircuit/KelpDaoProxy/KelpDaoProxy';
import * as Contracts from '../../../typechain-types';
import {
    CHAINID,
    WETH_ADDRESS,
    USDC_ADDRESS,
    USDT_ADDRESS,
    DAI_ADDRESS,
    UNISWAP_ROUTER_ADDRESS,
    AEVO_ADDRESS,
    AEVO_CONNECTOR_ADDRESS,
    USDC_IMPERSONATED_SIGNER_ADDRESS,
    USDT_IMPERSONATED_SIGNER_ADDRESS,
    DAI_IMPERSONATED_SIGNER_ADDRESS,
    ETH_PRICE_FEED_ADDRESS,
    USDT_PRICE_FEED_ADDRESS,
    DAI_PRICE_FEED_ADDRESS,
    RSETH_ETH_PRICE_FEED_ADDRESS,
    RSETH_ADDRESS,
    ZIRCUIT_DEPOSIT_ADDRESS,
    KELP_DEPOSIT_ADDRESS,
    KELP_DEPOSIT_REF_ID,
    NETWORK_COST,
} from '../../../constants';
import { BigNumberish, Signer } from 'ethers';
import { assert } from 'console';

const chainId: CHAINID = network.config.chainId;
console.log('chainId: ', chainId);
let receiveAddress: string;
const PRECISION = 2 * 1e6;
const ETH_AMOUNT = ethers.parseEther('1');
const ETH_AMOUNT_UHP = ethers.parseEther('2');

describe('KelpDaoProxy', () => {
    let admin: Signer,
        user1: Signer,
        user2: Signer,
        user3: Signer,
        user4: Signer;

    const usdcImpersonatedSigner =
        USDC_IMPERSONATED_SIGNER_ADDRESS[chainId] || '';
    const usdtImpersonatedSigner =
        USDT_IMPERSONATED_SIGNER_ADDRESS[chainId] || '';
    const daiImpersonatedSigner =
        DAI_IMPERSONATED_SIGNER_ADDRESS[chainId] || '';
    const usdcAddress = USDC_ADDRESS[chainId] || '';
    const usdtAddress = USDT_ADDRESS[chainId] || '';
    const daiAddress = DAI_ADDRESS[chainId] || '';
    const wethAddress = WETH_ADDRESS[chainId] || '';
    const rsEthAddress = RSETH_ADDRESS[chainId] || '';
    const swapRouterAddress = UNISWAP_ROUTER_ADDRESS[chainId] || '';
    const aevoAddress = AEVO_ADDRESS[chainId] || '';
    const aevoConnectorAddress = AEVO_CONNECTOR_ADDRESS[chainId] || '';
    const ethPriceFeed = ETH_PRICE_FEED_ADDRESS[chainId] || '';
    const rsEth_EthPriceFeed = RSETH_ETH_PRICE_FEED_ADDRESS[chainId] || '';
    const usdtPriceFeed = USDT_PRICE_FEED_ADDRESS[chainId] || '';
    const daiPriceFeed = DAI_PRICE_FEED_ADDRESS[chainId] || '';
    const kelpDepositAddress = KELP_DEPOSIT_ADDRESS[chainId] || '';
    const kelpDepositRefId = KELP_DEPOSIT_REF_ID[chainId] || '';
    const zircuitDepositAddress = ZIRCUIT_DEPOSIT_ADDRESS[chainId] || '';
    const networkCost = BigInt(Number(NETWORK_COST[chainId]) * 1e6);

    let kelpDaoProxyContract: Contracts.KelpDaoProxy;
    let uniSwapContract: Contracts.UniSwap;
    let priceConsumerContract: Contracts.PriceConsumer;
    let kelpZircuitRestakingStrategyContract: Contracts.KelpZircuitRestakingStrategy;
    let zircuitProxyContract: Contracts.IZircuitRestakeProxy;

    async function deployPriceConsumerContract() {
        const factory = await ethers.getContractFactory('PriceConsumer');

        priceConsumerContract = await factory.deploy(
            admin,
            [wethAddress, rsEthAddress, usdtAddress, daiAddress],
            [usdcAddress, wethAddress, usdcAddress, usdtAddress],
            [ethPriceFeed, rsEth_EthPriceFeed, usdtPriceFeed, daiPriceFeed]
        );
        await priceConsumerContract.waitForDeployment();

        console.log(
            'Deployed price consumer contract at address %s',
            await priceConsumerContract.getAddress()
        );
    }

    async function deployZircuitRestakProxy() {
        const factory = await ethers.getContractAt('IZircuitRestakeProxy');
        zircuitProxyContract = await factory.deploy(admin);
        await zircuitProxyContract.waitForDeployment();
        console.log(
            'Deployed zircuit restake proxy at address %s',
            await zircuitProxyContract.getAddress()
        );
    }

    async function deployUniSwapContract() {
        const factory = await ethers.getContractFactory('UniSwap');
        uniSwapContract = await factory.deploy(
            admin,
            swapRouterAddress,
            priceConsumerContract.getAddress()
        );
        await uniSwapContract.waitForDeployment();

        console.log(
            'Deployed uni swap contract at address %s',
            await uniSwapContract.getAddress()
        );
    }

    async function deployKelpDaoProxyContract() {
        const factory = await ethers.getContractFactory('KelpDaoProxy');
        kelpDaoProxyContract = await factory.deploy(
            kelpDepositAddress,
            zircuitDepositAddress,
            wethAddress
        );
        console.log(
            'Deploy kelp dao proxy contract at address %s',
            await kelpDaoProxyContract.getAddress()
        );
    }

    beforeEach(async () => {
        [admin, user1, user2, user3, user4] = await ethers.getSigners();
        receiveAddress = await user4.getAddress();

        //deploy
        await deployPriceConsumerContract();
        await deployUniSwapContract();
        await deployKelpDaoProxyContract();
        // await deployZircuitRestakProxy();
        console.log('Deploy smart contract');
    });

    it('Update restaking token test --- happy part', async () => {
        await kelpDaoProxyContract
            .connect(admin)
            .updateRestakingToken(wethAddress);
        expect(await kelpDaoProxyContract.getRestakingTokenCurrent()).to.equal(
            wethAddress
        );
    });

    it('Update restaking token test --- unhappy part', async () => {
        await kelpDaoProxyContract
            .connect(admin)
            .updateKelpWithdrawRestaking(wethAddress);
        expect(
            await kelpDaoProxyContract.getRestakingTokenCurrent()
        ).not.to.equal(usdcAddress);
    });

    it('Deposit ETH to kelp dao proxy --- happy part', async () => {
        await expect(() =>
            admin.sendTransaction({
                to: kelpDaoProxyContract.getAddress(),
                value: ETH_AMOUNT,
            })
        ).to.changeEtherBalance(kelpDaoProxyContract, ETH_AMOUNT);
        // await kelpDaoProxyContract.connect(admin).depositToRestakingProxy(kelpDepositRefId, { value: ETH_AMOUNT });
        let balance = await ethers.provider.getBalance(
            kelpDaoProxyContract.getAddress()
        );
        expect(await balance).to.equal(ETH_AMOUNT);
    });

    it('Deposit ETH to kelp dao proxy --- unhappy part', async () => {
        await expect(() =>
            admin.sendTransaction({
                to: kelpDaoProxyContract.getAddress(),
                value: ETH_AMOUNT,
            })
        ).to.changeEtherBalance(kelpDaoProxyContract, ETH_AMOUNT);
        // await kelpDaoProxyContract.connect(admin).depositToRestakingProxy(kelpDepositRefId, { value: ETH_AMOUNT });
        let balance = await ethers.provider.getBalance(
            kelpDaoProxyContract.getAddress()
        );
        expect(await balance).not.to.equal(ETH_AMOUNT_UHP);
    });
});
