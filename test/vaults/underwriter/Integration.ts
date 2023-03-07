import { ERC20Mock, UnderwriterVaultMock } from '../../../typechain';
import { BigNumber, Signer } from 'ethers';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  addDeposit,
  vaultSetup,
  caller,
  base,
  quote,
  receiver,
} from './VaultSetup';
import { setMaturities } from './UnderwriterVault';
import { formatEther, parseEther, parseUnits } from 'ethers/lib/utils';
import { expect } from 'chai';
import { increaseTo, now, ONE_DAY } from '../../../utils/time';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { ethers } from 'hardhat';
import { MockContract } from '@ethereum-waffle/mock-contract';

describe('#deposit', () => {
  for (const isCall of [true, false]) {
    let asset: ERC20Mock;
    let vault: UnderwriterVaultMock;
    let assetAmount = 2;
    let assetAmountEth: BigNumber;
    let balanceCaller: BigNumber;
    let balanceReceiver: BigNumber;

    describe(isCall ? 'call' : 'put', () => {
      describe('deposit into an empty vault', () => {
        beforeEach(async () => {
          const { callVault, putVault, base, quote, caller, receiver } =
            await loadFixture(vaultSetup);

          if (isCall) {
            asset = base;
            vault = callVault;
          } else {
            asset = quote;
            vault = putVault;
          }

          assetAmount = 2;
          assetAmountEth = parseEther(assetAmount.toString());
          balanceCaller = await asset.balanceOf(caller.address);
          balanceReceiver = await asset.balanceOf(receiver.address);

          await addDeposit(vault, caller, assetAmount, asset, quote, receiver);
        });

        it('vault should have received two asset amounts', async () => {
          expect(await asset.balanceOf(vault.address)).to.eq(assetAmountEth);
        });
        it('asset balance of caller should have been reduced by the asset amount', async () => {
          expect(await asset.balanceOf(caller.address)).to.eq(
            balanceCaller.sub(assetAmountEth),
          );
        });
        it('asset balance of receiver should be the same', async () => {
          expect(await asset.balanceOf(receiver.address)).to.eq(
            balanceReceiver,
          );
        });
        it('caller should not have received any shares', async () => {
          expect(await vault.balanceOf(caller.address)).to.eq(parseEther('0'));
        });
        it('receiver should have received the outstanding shares', async () => {
          expect(await vault.balanceOf(receiver.address)).to.eq(assetAmountEth);
        });
        it('total supply of the the vault should have increased by the asset amount ', async () => {
          expect(await vault.totalSupply()).to.eq(assetAmountEth);
        });
      });

      describe('deposit into a non-empty vault with a pricePerShare unequal to 1', () => {
        beforeEach(async () => {
          const { caller, receiver, callVault, putVault, base, quote } =
            await loadFixture(vaultSetup);
          if (isCall) {
            asset = base;
            vault = callVault;
          } else {
            asset = quote;
            vault = putVault;
          }
          await setMaturities(vault);
          assetAmount = 2;
          assetAmountEth = parseEther(assetAmount.toString());
          balanceCaller = await asset.balanceOf(caller.address);
          balanceReceiver = await asset.balanceOf(receiver.address);

          await addDeposit(vault, caller, 2, asset, quote, receiver);
          await vault.increaseTotalLockedSpread(parseEther('0.5'));
          await addDeposit(vault, caller, 2, base, quote, receiver);
        });
        it('vault should hold 4 units of the asset', async () => {
          // modify the price per share to (2 - 0.5) / 2 = 0.75
          expect(await asset.balanceOf(vault.address)).to.eq(parseEther('4'));
        });
        it('balance of the caller should be reduced by 4 units', async () => {
          expect(await asset.balanceOf(caller.address)).to.eq(
            balanceCaller.sub(parseEther('4')),
          );
        });
        it('balance of the receiver should be unchanged', async () => {
          expect(await asset.balanceOf(receiver.address)).to.eq(
            balanceReceiver,
          );
        });
        it('balance of vault shares of the caller should be 0', async () => {
          expect(await vault.balanceOf(caller.address)).to.eq(parseEther('0'));
        });
        it('balance of vault shares of the receiver should be 4.6666666..', async () => {
          expect(
            parseFloat(formatEther(await vault.balanceOf(receiver.address))),
          ).to.be.closeTo(2 + 2 / 0.75, 0.00001);
        });
      });
    });
  }
});

describe('#eventStream', () => {
  let startTime: number;

  let buyer1: SignerWithAddress;
  let buyer2: SignerWithAddress;
  let buyer3: SignerWithAddress;
  let depositor1: SignerWithAddress;
  let depositor2: SignerWithAddress;
  let depositor3: SignerWithAddress;

  async function createEventStream() {
    startTime = await now();

    const events = [
      {
        timestamp: startTime + ONE_DAY,
        spotPrice: 1000,
        config: {
          discriminator: 'deposit',
          assetAmount: 10,
          caller: depositor1,
          receiver: depositor1,
        },
      },
      {
        timestamp: startTime + 2 * ONE_DAY,
        spotPrice: 1000,
        config: {
          discriminator: 'buy',
          strike: 1000,
          maturity: 130000,
          size: 1.2,
        },
      },
    ];
    return { events };
  }

  interface Deposit {
    assetAmount: number;
    caller: SignerWithAddress;
    receiver: SignerWithAddress;
  }

  interface Mint {
    shareAmount: number;
    caller: SignerWithAddress;
    receiver: SignerWithAddress;
  }

  interface Withdraw {
    assetAmount: number;
    caller: SignerWithAddress;
    receiver: SignerWithAddress;
  }

  interface Redeem {
    shareAmount: number;
    caller: SignerWithAddress;
    receiver: SignerWithAddress;
  }

  interface Buy {
    strike: number;
    maturity: number;
    size: number;
    caller: SignerWithAddress;
    receiver: SignerWithAddress;
  }

  interface Event {
    timestamp: number;
    spotPrice: number;
    config: [Deposit, Mint, Withdraw, Redeem, Buy];
  }

  async function makeDeposit(
    args: Deposit,
    asset: ERC20Mock,
    vault: UnderwriterVaultMock,
  ) {
    const assetAmount = parseEther(args.assetAmount.toString());
    console.log('Increasing allowance.');
    await asset
      .connect(args.caller)
      .increaseAllowance(vault.address, assetAmount);
    console.log('Depositing assets.');
    await vault
      .connect(args.caller)
      .deposit(args.assetAmount, args.receiver.address);
  }

  async function makeMint(
    args: Mint,
    asset: ERC20Mock,
    vault: UnderwriterVaultMock,
  ) {
    const shareAmount = parseEther(args.shareAmount.toString());
    const assetAmount = await vault.convertToAssets(shareAmount);
    await asset
      .connect(args.caller)
      .increaseAllowance(vault.address, assetAmount);
    await vault.connect(args.caller).mint(shareAmount, args.receiver.address);
  }

  async function makeWithraw(args: Withdraw, vault: UnderwriterVaultMock) {
    const assetAmount = parseEther(args.assetAmount.toString());
    await vault
      .connect(args.caller)
      .withdraw(assetAmount, args.receiver.address, args.caller.address);
  }

  async function makeRedeem(args: Redeem, vault: UnderwriterVaultMock) {
    const shareAmount = parseEther(args.shareAmount.toString());
    await vault
      .connect(args.caller)
      .redeem(shareAmount, args.receiver.address, args.caller.address);
  }

  async function makeBuy(
    args: Buy,
    asset: ERC20Mock,
    vault: UnderwriterVaultMock,
  ) {
    const strike = parseEther(args.strike.toString());
    const quote = await vault.quote(strike, args.maturity, args.size);
    await asset
      .connect(args.caller)
      .increaseAllowance(vault.address, parseEther(quote.toString()));
    await vault.connect(args.caller).buy(strike, args.maturity, args.size);
  }

  async function getNextMaturities() {
    const currentTime = await now();
  }

  async function createSigners(base: ERC20Mock) {
    [buyer1, buyer2, buyer3, depositor1, depositor2, depositor3] =
      await ethers.getSigners();
    const signers = [
      buyer1,
      buyer2,
      buyer3,
      depositor1,
      depositor2,
      depositor3,
    ];
    console.log('Mint base asset.');
    for (let signer of signers) {
      await base.mint(signer.address, parseEther('100'));
    }
  }

  async function processEvents(
    vault: UnderwriterVaultMock,
    asset: ERC20Mock,
    oracleAdapter: MockContract,
    events: any,
  ) {
    function instanceOfDeposit(object: any): object is Deposit {
      return object.discriminator == 'deposit';
    }

    function instanceOfMint(object: any): object is Mint {
      return object.discriminator == 'Mint';
    }

    function instanceOfWithdraw(object: any): object is Withdraw {
      return object.discriminator == 'withdraw';
    }

    function instanceOfRedeem(object: any): object is Redeem {
      return object.discriminator == 'redeem';
    }

    function instanceOfBuy(object: any): object is Buy {
      return object.discriminator == 'buy';
    }

    function instanceOfEvent(object: any): object is Event {
      return 'timestamp' in object && 'spotPrice' in object;
    }

    for (const event of events) {
      if (instanceOfEvent(event)) {
        await increaseTo(event.timestamp);
        await oracleAdapter.mock.quote.returns(
          parseUnits(event.spotPrice.toString(), 18),
        );
        await oracleAdapter.mock.quoteFrom
          .withArgs(base.address, quote.address, event.timestamp)
          .returns(parseUnits(event.spotPrice.toString(), 18));

        if (instanceOfDeposit(event.config)) {
          await makeDeposit(event.config, asset, vault);
        } else if (instanceOfMint(event.config)) {
          await makeMint(event.config, asset, vault);
        } else if (instanceOfWithdraw(event.config)) {
          await makeWithraw(event.config, vault);
        } else if (instanceOfRedeem(event.config)) {
          await makeRedeem(event.config, vault);
        } else if (instanceOfBuy(event.config)) {
          await makeBuy(event.config, asset, vault);
        }
      } else {
        console.log('Invalid event!');
      }
    }
  }

  it('test event stream', async () => {
    console.log('Set up vault.');
    const { callVault, base, quote, oracleAdapter } = await vaultSetup();
    console.log('Create signers.');
    let asset: ERC20Mock;
    if (await callVault.isCall()) {
      asset = base;
    } else {
      asset = quote;
    }
    await createSigners(asset);
    console.log('Create event stream.');
    const { events } = await createEventStream();
    console.log(events);
    console.log('Process events.');
    await processEvents(callVault, asset, oracleAdapter, events);
  });
});
