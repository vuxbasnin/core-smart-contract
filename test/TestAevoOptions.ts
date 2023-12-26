import { ethers } from "hardhat";
import { expect } from "chai";
import * as Contracts from "../typechain-types";
import { BaseContract, Signer } from "ethers";

const aevoContractAbi = [{"inputs":[{"internalType":"address","name":"token_","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},{"inputs":[],"name":"AmountOutsideLimit","type":"error"},{"inputs":[],"name":"ConnectorUnavailable","type":"error"},{"anonymous":false,"inputs":[{"components":[{"internalType":"bool","name":"isLock","type":"bool"},{"internalType":"address","name":"connector","type":"address"},{"internalType":"uint256","name":"maxLimit","type":"uint256"},{"internalType":"uint256","name":"ratePerSecond","type":"uint256"}],"indexed":false,"internalType":"struct Vault.UpdateLimitParams[]","name":"updates","type":"tuple[]"}],"name":"LimitParamsUpdated","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"previousOwner","type":"address"},{"indexed":true,"internalType":"address","name":"newOwner","type":"address"}],"name":"OwnershipTransferStarted","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"previousOwner","type":"address"},{"indexed":true,"internalType":"address","name":"newOwner","type":"address"}],"name":"OwnershipTransferred","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"connector","type":"address"},{"indexed":false,"internalType":"address","name":"receiver","type":"address"},{"indexed":false,"internalType":"uint256","name":"unlockedAmount","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"pendingAmount","type":"uint256"}],"name":"PendingTokensTransferred","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"connector","type":"address"},{"indexed":false,"internalType":"address","name":"depositor","type":"address"},{"indexed":false,"internalType":"address","name":"receiver","type":"address"},{"indexed":false,"internalType":"uint256","name":"depositAmount","type":"uint256"}],"name":"TokensDeposited","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"connector","type":"address"},{"indexed":false,"internalType":"address","name":"receiver","type":"address"},{"indexed":false,"internalType":"uint256","name":"pendingAmount","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"totalPendingAmount","type":"uint256"}],"name":"TokensPending","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"connector","type":"address"},{"indexed":false,"internalType":"address","name":"receiver","type":"address"},{"indexed":false,"internalType":"uint256","name":"unlockedAmount","type":"uint256"}],"name":"TokensUnlocked","type":"event"},{"inputs":[],"name":"acceptOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"connectorPendingUnlocks","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"receiver_","type":"address"},{"internalType":"uint256","name":"amount_","type":"uint256"},{"internalType":"uint256","name":"msgGasLimit_","type":"uint256"},{"internalType":"address","name":"connector_","type":"address"}],"name":"depositToAppChain","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"address","name":"connector_","type":"address"}],"name":"getCurrentLockLimit","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"connector_","type":"address"}],"name":"getCurrentUnlockLimit","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"connector_","type":"address"}],"name":"getLockLimitParams","outputs":[{"components":[{"internalType":"uint256","name":"lastUpdateTimestamp","type":"uint256"},{"internalType":"uint256","name":"ratePerSecond","type":"uint256"},{"internalType":"uint256","name":"maxLimit","type":"uint256"},{"internalType":"uint256","name":"lastUpdateLimit","type":"uint256"}],"internalType":"struct Gauge.LimitParams","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"connector_","type":"address"},{"internalType":"uint256","name":"msgGasLimit_","type":"uint256"}],"name":"getMinFees","outputs":[{"internalType":"uint256","name":"totalFees","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"connector_","type":"address"}],"name":"getUnlockLimitParams","outputs":[{"components":[{"internalType":"uint256","name":"lastUpdateTimestamp","type":"uint256"},{"internalType":"uint256","name":"ratePerSecond","type":"uint256"},{"internalType":"uint256","name":"maxLimit","type":"uint256"},{"internalType":"uint256","name":"lastUpdateLimit","type":"uint256"}],"internalType":"struct Gauge.LimitParams","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"owner","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"pendingOwner","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"address","name":"","type":"address"}],"name":"pendingUnlocks","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes","name":"payload_","type":"bytes"}],"name":"receiveInbound","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"renounceOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"token__","outputs":[{"internalType":"contract ERC20","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"newOwner","type":"address"}],"name":"transferOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"receiver_","type":"address"},{"internalType":"address","name":"connector_","type":"address"}],"name":"unlockPendingFor","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"components":[{"internalType":"bool","name":"isLock","type":"bool"},{"internalType":"address","name":"connector","type":"address"},{"internalType":"uint256","name":"maxLimit","type":"uint256"},{"internalType":"uint256","name":"ratePerSecond","type":"uint256"}],"internalType":"struct Vault.UpdateLimitParams[]","name":"updates_","type":"tuple[]"}],"name":"updateLimitParams","outputs":[],"stateMutability":"nonpayable","type":"function"}];

describe("OptionsTestVault Contract", function () {
  let aevoOptions: Contracts.AevoOptions;
  let deployer: Signer;
  let user: Signer;
  let bridgedUsdc: Contracts.IERC20;
  const aevoAddress = "0x80d40e32FAD8bE8da5C6A42B8aF1E181984D137c";
  const aevoConnectorAddress = "0x69Adf49285c25d9f840c577A0e3cb134caF944D3";
  let optionsReceiver: string;
  const cap = ethers.parseUnits("1000000", 18);

  const assetAddress = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"; // Bridged USDC's address

  async function deployAevoOptions(): Promise<string> {
    const AevoOptions = await ethers.getContractFactory("AevoOptions");
    aevoOptions = await AevoOptions.deploy(assetAddress, aevoAddress);

    await aevoOptions.waitForDeployment();
    const aevoOptionsAddress = await aevoOptions.getAddress();
    console.log(`AevoOptions deployed to: ${aevoOptionsAddress}`);

    return aevoOptionsAddress;
  }

  before(async function () {
    // Get signers
    [deployer, user] = await ethers.getSigners();
    console.log("User = %s", await user.getAddress());

    console.log(
      "Deploying contracts with the account:",
      await deployer.getAddress()
    );

    // Deploy AevoOptions and set optionsVendorProxy
    const aevoOptionsAddress = await deployAevoOptions();

    optionsReceiver = await user.getAddress();

    const impersonatedSigner = await ethers.getImpersonatedSigner(
      "0x226bf1ee0bb0cf647f6a9f0d8b380d6ab56de3cb"
    );
    console.log("address 1", await impersonatedSigner.getAddress());

    // Connect to the asset contract (assuming ERC20)
    bridgedUsdc = await ethers.getContractAt("IERC20", assetAddress);
    console.log(
      "balance of 1",
      await bridgedUsdc
        .connect(impersonatedSigner)
        .balanceOf(await impersonatedSigner.getAddress())
    );

    const transferTx = await bridgedUsdc
      .connect(impersonatedSigner)
      .transfer(optionsReceiver, ethers.parseUnits("1000", 6)); // Transferring 1000 USDC
    await transferTx.wait();

    const balanceOfUser = await bridgedUsdc
      .connect(user)
      .balanceOf(optionsReceiver);
    console.log("Balance of user %s", balanceOfUser);
  });

//   it("should deposit tokens to the OptionsTestVault", async function () {
//     // First, approve the OptionsTestVault contract to spend tokens
//     const depositAmount = ethers.parseUnits("1000", 6);
//     const tx1 = await bridgedUsdc
//       .connect(user)
//       .approve(aevoAddress, depositAmount);
//     await tx1.wait();

//     const tx2 = await bridgedUsdc
//       .connect(user)
//       .approve(await aevoOptions.getAddress(), depositAmount);
//     await tx2.wait();

//     // Then, deposit tokens to the OptionsTestVault
//     await aevoOptions
//       .connect(user)
//       .depositToVendor(
//         await user.getAddress(),
//         depositAmount,
//         aevoConnectorAddress
//       );

//     console.log("deposited to vault");

//   });
  it("should deposit tokens to AEVO directly", async function () {

    // const provider = new ethers.providers.JsonRpcProvider(`https://arbitrum-mainnet.infura.io/v3/85cde589ce754dafa0a57001c326104d`);
    // First, approve the OptionsTestVault contract to spend tokens
    const depositAmount = ethers.parseUnits("1000", 6);
    const tx1 = await bridgedUsdc
      .connect(user)
      .approve(aevoAddress, depositAmount);
    await tx1.wait();

    const aevoContract = new ethers.Contract(aevoAddress, aevoContractAbi, user);

    const tx2 = await bridgedUsdc
      .connect(user)
      .approve(aevoAddress, depositAmount);
    await tx2.wait();

    // Then, deposit tokens to the OptionsTestVault
    await aevoContract
      .connect(user)
      .depositToAppChain(
        await user.getAddress(),
        depositAmount,
        1000000,
        aevoConnectorAddress
      );

    console.log("deposited to vault");

  });
});
