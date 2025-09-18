import {
    AccountWallet,
    PXE,
    Fr,
    L1FeeJuicePortalManager,
    FeeJuicePaymentMethodWithClaim,
    Schnorr,
    GrumpkinScalar,
    Fq,
} from "@aztec/aztec.js";
import { CheatCodes } from "@aztec/aztec.js/testing"
import { getInitialTestAccountsManagers } from "@aztec/accounts/testing";
import {
    deployEscrowContract,
    deployTokenContractWithMinter,
    wad,
    depositToEscrow,
    createPXE,
    getFeeJuicePortalManager,
    TOKEN_METADATA,
    expectBalancePrivate,
    CardEscrowContract,
    TokenContract,
    setupAccountWithFeeClaim,
    createCheatCodes,
    buildSignedEscrowMessage
} from "../src";

export const computeEpoch = async (cc: CheatCodes): Promise<Fr> => {
    const timestamp = await cc.aztec.timestamp();
    return new Fr(Math.floor(timestamp / 86400));
}

describe("Private Transfer Demo Test", () => {
    let userPXE: PXE;
    let operatorPXE: PXE;
    let userCC: CheatCodes;
    let operatorCC: CheatCodes;

    let minter: AccountWallet;
    let user: AccountWallet;

    let operator: AccountWallet;

    let escrowMasterKey: Fr;

    let escrow: CardEscrowContract;
    let usdc: TokenContract;

    let operatorFeeJuicePortalManager: L1FeeJuicePortalManager;

    const INITIAL_SPEND_LIMIT = wad(1000n, 6n);
    const MINT_AMOUNT = wad(10000n, 6n);

    beforeAll(async () => {
        // setup PXE connections
        userPXE = await createPXE();
        // operatorPXE = await createPXE(1);
        operatorPXE = userPXE;
        userCC = await createCheatCodes(userPXE);
        operatorCC = await createCheatCodes(operatorPXE);

        // get PXE 1 accounts
        const wallets = await Promise.all(
            (await getInitialTestAccountsManagers(userPXE)).map(m => m.register())
        );
        minter = wallets[0];
        user = wallets[1];

        // deploy PXE2 account
        // NOTE: must allow two transactions to pass before claiming
        operatorFeeJuicePortalManager = await getFeeJuicePortalManager(operatorPXE);
        const {
            claim: operatorClaim,
            wallet: operatorWallet,
            account: operatorAccount
        } = await setupAccountWithFeeClaim(operatorPXE, operatorFeeJuicePortalManager);
        operator = operatorWallet;

        // deploy token contract and mint
        usdc = await deployTokenContractWithMinter(TOKEN_METADATA.usdc, minter);
        await usdc
            .withWallet(minter)
            .methods.mint_to_private(
                minter.getAddress(),
                user.getAddress(),
                MINT_AMOUNT
            )
            .send()
            .wait();

        // claim fee juice for user and deploy
        const claimAndPay = new FeeJuicePaymentMethodWithClaim(operator, operatorClaim);
        await operatorAccount.deploy({ fee: { paymentMethod: claimAndPay } }).wait();

        // register accounts and contracts in each PXE
        await userPXE.registerSender(user.getAddress());
        await operatorPXE.registerSender(minter.getAddress());
        await operatorPXE.registerSender(user.getAddress());
        await operatorPXE.registerContract(usdc);

    });

    test.skip("check escrow key leaking", async () => {
        // deploy new escrow instance
        ({ contract: escrow, secretKey: escrowMasterKey } = await deployEscrowContract(
            userPXE,
            user,
            usdc.address,
            operator.getAddress(),
            { x: 0n, y: 0n }, // don't care about pubkey here
            INITIAL_SPEND_LIMIT
        ));

        // Check seller Escrow
        const sellerDefinition = await escrow
            .withWallet(user)
            .methods.get_config()
            .simulate();
        expect(sellerDefinition.owner).not.toEqual(0n);

        // register contract but do not register decryption keys
        // if contract is not registered they definitely can't call it
        await operatorPXE.registerContract(escrow);

        // check if maker note exists
        expect(async () => {
            await escrow
                .withWallet(operator)
                .methods.get_config()
                .simulate();
        }).toThrow()

        // add account to buyer pxe
        await operatorPXE.registerAccount(escrowMasterKey, await escrow.partialAddress);
        await escrow.withWallet(operator).methods.sync_private_state().simulate();
        const buyerDefinition = await escrow
            .withWallet(operator)
            .methods
            .get_config()
            .simulate();
        // expect(buyerDefinition.owner).toEqual(escrow.address.toBigInt());
        expect(buyerDefinition.owner).not.toEqual(0n);
    });
});
