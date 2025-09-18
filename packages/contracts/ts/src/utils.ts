import { AztecAddress, createPXEClient, Fq, Fr, PXE, Schnorr, waitForPXE } from "@aztec/aztec.js";
import { CheatCodes } from "@aztec/aztec.js/testing";
import { SIGNED_ACTION_TYPE } from "./constants";
import { poseidon2Hash } from "@aztec/foundation/crypto";

export const createPXE = async (id: number = 0) => {
    const { BASE_PXE_URL = `http://localhost` } = process.env;
    const url = `${BASE_PXE_URL}:${8080 + id}`;
    const pxe = createPXEClient(url);
    await waitForPXE(pxe);
    return pxe;
};

export const createCheatCodes = async (pxe: PXE) => {
    const { L1_RPC_URL = `http://localhost:8545` } = process.env;
    return await CheatCodes.create([L1_RPC_URL], pxe);
}

export const wad = (n: bigint = 1n, decimals: bigint = 18n) =>
    n * 10n ** decimals;


export const isTestnet = async (pxe: PXE): Promise<boolean> => {
    const chainId = (await pxe.getNodeInfo()).l1ChainId;
    return chainId === 11155111; // Sepolia testnet
}

export const buildSignedEscrowMessage = async (
    signingKey: Fq,
    contractAddress: AztecAddress,
    value: bigint,
    nonce: Fr,
    action: SIGNED_ACTION_TYPE
): Promise<Buffer> =>  {
    const schnorr = new Schnorr();
    
    const message = await poseidon2Hash([
        contractAddress.toBigInt(),
        value,
        nonce,
        action === "spendLimit" ? 1n : 2n,
    ]).then(message => message.toBuffer());

    const signature = await schnorr.constructSignature(message, signingKey);
    return signature.toBuffer();
}