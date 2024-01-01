import { ethers } from "hardhat";

async function main() {
  const privateKey =
    "0xea7aab9140a5b271551c74b1a12933c793eeef19cdbf466409a9e46e30b4d7ba"; // Replace with your MetaMask private key
  const contractAddress = "0x5E13f306c07ADB7Fac0f5cB9d834598446f31f31"; // Replace with your contract's address
  const usdcAddress = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"; // USDC contract address

  // Connect to the wallet
  const wallet = new ethers.Wallet(privateKey, ethers.provider);
  const arbProvider = new ethers.JsonRpcProvider("https://arbitrum-mainnet.infura.io/v3/85cde589ce754dafa0a57001c326104d");

  // Connect to the USDC contract
  const usdcContract = await ethers.getContractAt("IERC20", usdcAddress);

  console.log(
    "balance of 1",
    await usdcContract.connect(wallet).balanceOf(await wallet.getAddress())
  );

  // Connect to the OptionsTestVault contract
  const optionsTestVaultContract = await ethers.getContractAt(
    "OptionsTestVault",
    contractAddress
  );

  // Amount to deposit (5 USDC with 6 decimal places)
  const depositAmount = ethers.parseUnits("1", 6);

  // Approve the OptionsTestVault contract to spend USDC
  console.log("Approving USDC transfer...");
  const approveTx = await usdcContract
    .connect(wallet)
    .approve(contractAddress, depositAmount);
  await approveTx.wait();

  // Deposit USDC to the OptionsTestVault contract
  console.log("Depositing USDC to OptionsTestVault...");
  const depositTx = await optionsTestVaultContract.connect(wallet).deposit(depositAmount);
  await depositTx.wait();

  // Deposit USDC to the OptionsTestVault contract
  console.log("Depositing USDC to vendor...");
  
  const depositTx1 = await optionsTestVaultContract.connect(wallet).depositToVendor(
    depositAmount,
    {
      value: ethers.parseEther("0.001753"),
      gasLimit: 3000000,
      gasPrice: (await arbProvider.getFeeData()).gasPrice
    }
  );
  await depositTx1.wait();

  // const withdrawalTx = await optionsTestVaultContract.withdraw(depositAmount);
  // console.log("Withdrawal tx %s", withdrawalTx.hash);
  // await withdrawalTx.wait();

  console.log("Deposit successful!");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
