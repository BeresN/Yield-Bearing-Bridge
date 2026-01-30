import { readFileSync, existsSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { decryptKeystore } from "@ethersproject/json-wallets";
import password from "@inquirer/password";

/**
 * Loads and decrypts a Foundry keystore
 * @param accountName Name of the account (from `cast wallet list`)
 * @returns Decrypted private key
 */
export async function loadFoundryKeystore(accountName: string): Promise<`0x${string}`> {
  // Foundry keystores are stored in ~/.foundry/keystores/
  const keystorePath = join(homedir(), ".foundry", "keystores", accountName);

  if (!existsSync(keystorePath)) {
    throw new Error(
      `Keystore not found: ${keystorePath}\n` +
        `Create one with: cast wallet import ${accountName} --interactive`
    );
  }

  console.log(`\nLoading keystore: ${accountName}`);

  const keystoreJson = readFileSync(keystorePath, "utf-8");

  const keystorePassword = await password({
    message: "Enter keystore password:",
    mask: "*",
  });

  console.log("Decrypting keystore (this may take a moment)...");

  try {
    const wallet = await decryptKeystore(keystoreJson, keystorePassword);
    console.log(`Wallet loaded: ${wallet.address}\n`);
    return wallet.privateKey as `0x${string}`;
  } catch (error: any) {
    if (error.message?.includes("invalid password")) {
      throw new Error("Invalid password");
    }
    throw error;
  }
}
