// Note: Should update priceConsumerAddress and redeploy camelotSwapContract before deploy the vault in next release
import { ethers, network } from "hardhat";

import {
    CHAINID,
    WETH_ADDRESS,
    USDC_ADDRESS,
    UNISWAP_ROUTER_ADDRESS,
    AEVO_ADDRESS,
    AEVO_CONNECTOR_ADDRESS,
    EZETH_ADDRESS,
    ZIRCUIT_DEPOSIT_ADDRESS,
    RENZO_DEPOSIT_ADDRESS,
    PRICE_CONSUMER_ADDRESS
} from "../constants";
import * as Contracts from "../typechain-types";

const chainId: CHAINID = network.config.chainId ?? 0;
console.log("chainId ",chainId);

const aevoRecipientAddress = "0x0aDf03D895617a95F317892125Cd6fb9ca3b99c1";
const usdcAddress = USDC_ADDRESS[chainId] || "";
const wethAddress = WETH_ADDRESS[chainId] || "";
const ezEthAddress = EZETH_ADDRESS[chainId] || "";
const swapRouterAddress = UNISWAP_ROUTER_ADDRESS[chainId] || "";
const aevoAddress = AEVO_ADDRESS[chainId] || "";
const aevoConnectorAddress = AEVO_CONNECTOR_ADDRESS[chainId] || "";
const renzoDepositAddress = RENZO_DEPOSIT_ADDRESS[chainId] || "";
const zircuitDepositAddress = ZIRCUIT_DEPOSIT_ADDRESS[chainId] || "";
  
let renzoRestakingDNVault: Contracts.RenzoRestakingDeltaNeutralVault;
let uniSwapContract: Contracts.UniSwap;

async function deployUniSwapContract() {
    const priceConsumerAddress = PRICE_CONSUMER_ADDRESS[chainId] || "";

    const factory = await ethers.getContractFactory("UniSwap");
    uniSwapContract = await factory.deploy(
      swapRouterAddress,
      priceConsumerAddress
    );
    await uniSwapContract.waitForDeployment();

    console.log(
      "Deployed uni swap contract at address %s",
      await uniSwapContract.getAddress()
    );
}

async function deployRenzoRestakingDeltaNeutralVault() {
    const renzoRestakingDeltaNeutralVault = await ethers.getContractFactory(
      "RenzoRestakingDeltaNeutralVault"
    );

    // const uniswapContract = await uniSwapContract.getAddress();
    const uniswapContract = "0x29253ff85A972D6582CaCC16424744705C5BAF3b";

    renzoRestakingDNVault = await renzoRestakingDeltaNeutralVault.deploy(
      usdcAddress,
      wethAddress,
      uniswapContract,
      aevoAddress,
      aevoRecipientAddress,
      aevoConnectorAddress,
      ezEthAddress,
      BigInt(1 * 1e6),
      [renzoDepositAddress, zircuitDepositAddress],
      [500, 100]
    );
    await renzoRestakingDNVault.waitForDeployment();

    console.log(
      "deploy rockOnyxDeltaNeutralVaultContract successfully: %s",
      await renzoRestakingDNVault.getAddress()
    );
}

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log(
    "Deploying contracts with the account:",
    await deployer.getAddress()
  );

  // MAINNET
  
  // await deployUniSwapContract();
  
  await deployRenzoRestakingDeltaNeutralVault();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
