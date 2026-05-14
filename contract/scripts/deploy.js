import { network } from "hardhat";
import { ethers as ethersLib } from "ethers";

const { ethers } = await network.create("zeroG");

const provider = ethers.provider;
const wallet = new ethersLib.Wallet(process.env.PRIVATE_KEY, provider);

console.log("Deploying with:", wallet.address);

const voidToken = await ethers.deployContract("VOIDToken", [], wallet);
await voidToken.waitForDeployment();
const voidAddress = await voidToken.getAddress();
console.log("VOIDToken deployed to:", voidAddress);

const arena = await ethers.deployContract("OblivionArena", [voidAddress], wallet);
await arena.waitForDeployment();
const arenaAddress = await arena.getAddress();
console.log("OblivionArena deployed to:", arenaAddress);

const tx = await voidToken.connect(wallet).setArenaContract(arenaAddress);
await tx.wait();
console.log("Arena wired to VOIDToken");

console.log("\n--- COPY THESE INTO YOUR .env ---");
console.log("VITE_VOID_TOKEN_ADDRESS=" + voidAddress);
console.log("VITE_ARENA_ADDRESS=" + arenaAddress);
