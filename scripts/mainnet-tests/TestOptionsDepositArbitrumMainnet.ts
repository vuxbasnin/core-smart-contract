import { ethers } from "hardhat";

async function main() {
  const privateKey = "0xea7aab9140a5b271551c74b1a12933c793eeef19cdbf466409a9e46e30b4d7ba"; // Replace with your MetaMask private key
  const contractAddress = "0xB6a11BE5B2eB81C95f21d21baBEe68B2c17001FD"; // Replace with your contract's address
  const usdcAddress = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"; // USDC contract address

  // Connect to the wallet
  const wallet = new ethers.Wallet(privateKey, ethers.provider);

  // Connect to the USDC contract
  const usdcContract = await ethers.getContractAt("IERC20", usdcAddress);

  console.log(
    "balance of 1",
    await usdcContract
      .connect(wallet)
      .balanceOf(await wallet.getAddress())
  );

  // Connect to the OptionsTestVault contract
  const optionsTestVaultContract = await ethers.getContractAt("OptionsTestVault", contractAddress);

  // Amount to deposit (5 USDC with 6 decimal places)
  const depositAmount = ethers.parseUnits("5", 6);

  // Approve the OptionsTestVault contract to spend USDC
  console.log("Approving USDC transfer...");
  const approveTx = await usdcContract.connect(wallet).approve(contractAddress, depositAmount);
  await approveTx.wait();

  // Deposit USDC to the OptionsTestVault contract
  console.log("Depositing USDC to OptionsTestVault...");
  const depositTx = await optionsTestVaultContract.deposit(depositAmount);
  await depositTx.wait();

  // Deposit USDC to the OptionsTestVault contract
  console.log("Depositing USDC to OptionsTestVault...");
  const depositTx1 = await optionsTestVaultContract.depositToVendor(depositAmount);
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
