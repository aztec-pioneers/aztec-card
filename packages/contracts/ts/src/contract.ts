import {
    Contract,
    AztecAddress,
    Fr,
    deriveKeys,
    PXE,
    DeployOptions,
    TxHash,
    AccountWallet,
    createAztecNodeClient,
    SendMethodOptions,
    WaitOpts,
} from "@aztec/aztec.js";
import { computeContractAddressFromInstance, computePartialAddress, ContractInstanceWithAddress, getContractClassFromArtifact } from "@aztec/stdlib/contract";
import {
    CardEscrowContract,
    CardEscrowContractArtifact,
    TokenContract,
    TokenContractArtifact
} from "./artifacts";

/**
 * Deploys a new instance of the Aztec Card Escrow Contract
 * @dev ensures contract is built with known encryption keys and adds to deployer PXE
 * 
 * @param pxe - the PXE of the deploying account
 * @param deployer - the account deploying the Aztec Card Escrow Contract
 * @param tokenAddress - the address of the token debited by the card operator
 * @param operatorAddress - address of the account allowed to debit the card
 * @param spendLimit - the initial maximum amount that can be spent by the operator
 * @param opts - Aztec function send and wait options (optional)
 * @returns
 *          contract - the deployed Aztec Card Escrow Contract
 *          secretKey - the master key for the contract
 */
export async function deployEscrowContract(
    pxe: PXE,
    deployer: AccountWallet,
    tokenAddress: AztecAddress,
    operatorAddress: AztecAddress,
    operatorSchnorrPubkey: { x: bigint, y: bigint },
    spendLimit: bigint,
    opts: { deploy?: DeployOptions, wait?: WaitOpts } = {}
): Promise<{ contract: CardEscrowContract, secretKey: Fr }> {
    // get keys for contract
    const contractSecretKey = Fr.random();
    const contractPublicKeys = (await deriveKeys(contractSecretKey)).publicKeys;

    // set up contract deployment tx
    const contractDeployment = await Contract.deployWithPublicKeys(
        contractPublicKeys,
        deployer,
        CardEscrowContractArtifact,
        [
            tokenAddress,
            operatorAddress,
            operatorSchnorrPubkey.x,
            operatorSchnorrPubkey.y,
            spendLimit
        ],
    );

    // add contract decryption keys to PXE
    const partialAddress = await computePartialAddress(
        await contractDeployment.getInstance(),
    );
    await pxe.registerAccount(contractSecretKey, partialAddress);
    // deploy contract
    const contract = await contractDeployment
        .send(opts.deploy)
        .deployed(opts.wait);
    return {
        contract: contract as CardEscrowContract,
        secretKey: contractSecretKey,
    };
}

/**
 * Deploys a new instance of Defi-Wonderland's Fungible Token Contract
 * @param tokenMetadata - the name, symbol, and decimals of the token
 * @param deployer - the account deploying the token contract (gets minter rights)
 * @param opts - Aztec function send and wait options (optional)
 * @returns - the deployed Token Contract
 */
export async function deployTokenContractWithMinter(
    tokenMetadata: { name: string; symbol: string; decimals: number },
    deployer: AccountWallet,
    opts: { deploy?: DeployOptions, wait?: WaitOpts } = {}
): Promise<TokenContract> {
    const contract = await Contract.deploy(
        deployer,
        TokenContractArtifact,
        [
            tokenMetadata.name,
            tokenMetadata.symbol,
            tokenMetadata.decimals,
            deployer.getAddress(),
            AztecAddress.ZERO,
        ],
        "constructor_with_minter",
    )
        .send(opts.deploy)
        .deployed(opts.wait);
    return contract as TokenContract;
}

export async function depositToEscrow(
    escrow: CardEscrowContract,
    caller: AccountWallet,
    token: TokenContract,
    amount: bigint,
    opts: { send?: SendMethodOptions, wait?: WaitOpts } = {}
): Promise<TxHash> {
    escrow = escrow.withWallet(caller);
    // create authwit
    const nonce = Fr.random();
    const authwit = await caller.createAuthWit({
        caller: escrow.address,
        action: token.methods.transfer_private_to_private(
            caller.getAddress(),
            escrow.address,
            amount,
            nonce,
        ),
    });
    // send transfer_in with authwit
    const receipt = await escrow
        .methods
        .deposit(amount, nonce)
        .with({ authWitnesses: [authwit], })
        .send(opts.send)
        .wait(opts.wait);
    // return tx hash
    return receipt.txHash;
}


/**
 * Checks that a private balance of a token for a specific address matches expectations
 * @param token - the token balance to query
 * @param address - the address of the token holder
 * @param expectedBalance - the balance expected to be returned
 * @returns - true if balance matches expectations, and false otherwise
 */
export async function expectBalancePrivate(
    token: TokenContract,
    address: AztecAddress,
    expectedBalance: bigint
): Promise<boolean> {
    const empiricalBalance = await token
        .methods
        .balance_of_private(address)
        .simulate();
    return empiricalBalance === expectedBalance;
}

export const getTokenContract = async (
    pxe: PXE,
    caller: AccountWallet,
    tokenAddress: AztecAddress,
    aztecRpcUrl: string = "http://localhost:8080"
): Promise<TokenContract> => {
    const node = createAztecNodeClient(aztecRpcUrl);
   

    const contractInstance = await node.getContract(tokenAddress);
    if (!contractInstance) {
        throw new Error(`No instance for token contract at ${tokenAddress.toString()} found!`);
    }
    await pxe.registerContract({
        instance: contractInstance,
        artifact: TokenContractArtifact
    });
    const token = await TokenContract.at(tokenAddress, caller);
    await token.methods.sync_private_state().simulate();
    return token;
};

export const getEscrowContract = async (
    pxe: PXE,
    caller: AccountWallet,
    escrowAddress: AztecAddress,
    contractInstance: ContractInstanceWithAddress,
    escrowSecretKey: Fr,
    escrowPartialAddress: Fr
): Promise<CardEscrowContract> => {
    // register contract & contract account
    await pxe.registerContract({
        instance: contractInstance,
        artifact: CardEscrowContractArtifact
    });
    await pxe.registerAccount(escrowSecretKey, escrowPartialAddress);
    await pxe.registerSender(escrowAddress);
    const escrow = await CardEscrowContract.at(escrowAddress, caller);
    await escrow.methods.sync_private_state().simulate();
    return escrow;
};

/**
 * Validates that a claimed contract address matches the address computed from the contract instance
 *
 * @param claimedAddress - The address claimed by the user
 * @param instance - The contract instance to validate
 * @returns - True if the addresses match, false otherwise
 */
export const validateContractAddress = async (
  claimedAddress: AztecAddress,
  instance: ContractInstanceWithAddress,
): Promise<boolean> => {
  const computed = await computeContractAddressFromInstance(instance);
  return computed.equals(claimedAddress);  
}