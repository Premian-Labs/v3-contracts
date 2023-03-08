import {
  ERC20Mock,
  IPoolMock__factory,
  UnderwriterVaultMock,
} from '../../../typechain';
import { BigNumber, Signer } from 'ethers';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  addDeposit,
  vaultSetup,
  caller,
  receiver,
  createPool,
  poolKey,
} from './VaultSetup';
import { setMaturities } from './UnderwriterVault';
import { formatEther, parseEther, parseUnits } from 'ethers/lib/utils';
import { expect } from 'chai';
import {
  getValidMaturity,
  increaseTo,
  now,
  ONE_DAY,
} from '../../../utils/time';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { ethers } from 'hardhat';
import { MockContract } from '@ethereum-waffle/mock-contract';
import { PoolUtil } from '../../../utils/PoolUtil';

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

    const { t0, t1, t2, t3 } = await getNextMaturities();

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
        timestamp: null,
        spotPrice: 1000,
        config: {
          discriminator: 'buy',
          strike: 1000,
          maturity: t0,
          size: 1.2,
          caller: buyer1,
          receiver: buyer1,
        },
      },
      {
        timestamp: null,
        spotPrice: 1000,
        config: {
          discriminator: 'mint',
          assetAmount: 10,
          caller: depositor2,
          receiver: depositor2,
        },
      },
      {
        timestamp: t0,
        spotPrice: null,
        config: {
          discriminator: 'settle',
        },
      },
    ];
    return { events };
  }

  async function setSpotPriceMaturities(
    base: ERC20Mock,
    quote: ERC20Mock,
    oracleAdapter: MockContract,
  ) {
    const { t0, t1, t2, t3 } = await getNextMaturities();
    await oracleAdapter.mock.quoteFrom
      .withArgs(base.address, quote.address, t0)
      .returns(parseEther('1100'));
    await oracleAdapter.mock.quoteFrom
      .withArgs(base.address, quote.address, t1)
      .returns(parseEther('1200'));
    await oracleAdapter.mock.quoteFrom
      .withArgs(base.address, quote.address, t2)
      .returns(parseEther('1500'));
    await oracleAdapter.mock.quoteFrom
      .withArgs(base.address, quote.address, t3)
      .returns(parseEther('900'));
  }

  async function createPools(
    deployer: SignerWithAddress,
    base: ERC20Mock,
    quote: ERC20Mock,
    oracleAdapter: MockContract,
    p: PoolUtil,
  ) {
    const { t0, t1, t2, t3 } = await getNextMaturities();
    let strikes: any = {};
    strikes[t0] = [500, 700, 1000, 1300, 1500];
    strikes[t1] = [500, 700, 1000, 1300, 1500];
    strikes[t2] = [500, 700, 1000, 1300, 1500];
    strikes[t3] = [500, 700, 1000, 1300, 1500];

    await createPool(
      parseEther('1000'),
      t0,
      true,
      deployer,
      base,
      quote,
      oracleAdapter,
      p,
    );
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
    console.log('Make deposit.');
    const assetAmount = parseEther(args.assetAmount.toString());
    await asset
      .connect(args.caller)
      .increaseAllowance(vault.address, assetAmount);
    await vault
      .connect(args.caller)
      .deposit(assetAmount, args.receiver.address);
  }

  async function makeMint(
    args: Mint,
    asset: ERC20Mock,
    vault: UnderwriterVaultMock,
  ) {
    console.log('Make mint.');
    const shareAmount = parseEther(args.shareAmount.toString());
    const assetAmount = await vault.convertToAssets(shareAmount);
    await asset
      .connect(args.caller)
      .increaseAllowance(vault.address, assetAmount);
    await vault.connect(args.caller).mint(shareAmount, args.receiver.address);
  }

  async function makeWithraw(args: Withdraw, vault: UnderwriterVaultMock) {
    console.log('Make withdraw.');
    const assetAmount = parseEther(args.assetAmount.toString());
    await vault
      .connect(args.caller)
      .withdraw(assetAmount, args.receiver.address, args.caller.address);
  }

  async function makeRedeem(args: Redeem, vault: UnderwriterVaultMock) {
    console.log('Make redeem.');
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
    console.log('Make buy.');
    const strike = parseEther(args.strike.toString());
    const size = parseEther(args.size.toString());
    const [, price, mintingFee] = await vault.quote(
      strike,
      BigNumber.from(args.maturity),
      size,
    );
    const allowance =
      parseFloat(formatEther(price)) + parseFloat(formatEther(mintingFee));
    await asset
      .connect(args.caller)
      .increaseAllowance(vault.address, parseEther(allowance.toString()));
    await vault.connect(args.caller).buy(strike, args.maturity, size);
  }

  async function makeSettle(
    vault: UnderwriterVaultMock,
    deployer: SignerWithAddress,
  ) {
    console.log('Make settle.');
    await vault.connect(deployer).settle();
  }

  async function getNextMaturities() {
    const diffs = [7, 14, 21, 28];

    let arr = [];
    let nextFriday: any;
    let unixTime: number;

    for (let diff of diffs) {
      const t = new Date().getDate() + (6 - new Date().getDay() - 1) + diff;
      nextFriday = new Date();
      nextFriday.setDate(t);
      nextFriday.setUTCHours(0, 0, 0, 0);
      unixTime = Math.floor(nextFriday.getTime() / 1000);
      arr.push(unixTime);
    }

    return { t0: arr[0], t1: arr[1], t2: arr[2], t3: arr[3] };
  }

  async function createSigners(base: ERC20Mock) {
    [buyer1, buyer2, buyer3, depositor1, depositor2, depositor3] =
      await ethers.getSigners();
  }

  async function checkTotalAssetsLeakage(
    vault: UnderwriterVaultMock,
    deployer: SignerWithAddress,
    asset: ERC20Mock,
  ) {
    const signers = [
      buyer1,
      buyer2,
      buyer3,
      depositor1,
      depositor2,
      depositor3,
    ];
    console.log('Check totalAssets for leakage.');

    let totalAssets: number = 0;
    for (let signer of signers) {
      let balanceAsset = parseFloat(
        formatEther(await asset.balanceOf(signer.address)),
      );
      console.log('signer', signer.address, balanceAsset);
      totalAssets += balanceAsset;
    }
    const poolAddresses = await vault.getPoolAddresses();
    for (let poolAddress of poolAddresses) {
      //IPoolMock__factory.connect(poolAddress, deployer);
      let balanceAsset = parseFloat(
        formatEther(await asset.balanceOf(poolAddress)),
      );
      console.log('pool', poolAddress, balanceAsset);
      totalAssets += balanceAsset;
    }
    let balanceAsset = parseFloat(
      formatEther(await asset.balanceOf(vault.address)),
    );
    console.log('vault', vault.address, balanceAsset);
    totalAssets += balanceAsset;
    expect(totalAssets).to.be.closeTo(6000, 0.1);
  }

  async function processEvents(
    vault: UnderwriterVaultMock,
    asset: ERC20Mock,
    deployer: SignerWithAddress,
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

    function instanceOfSettle(object: any): object is Buy {
      return object.discriminator == 'settle';
    }

    function instanceOfEvent(object: any): object is Event {
      return 'timestamp' in object && 'spotPrice' in object;
    }

    // the integration test is a zero-sum game - the total amount of assets is fixed
    for (const event of events) {
      if (instanceOfEvent(event)) {
        if (typeof event.timestamp == 'number')
          await increaseTo(event.timestamp);
        if (typeof event.spotPrice == 'number')
          await oracleAdapter.mock.quote.returns(
            parseUnits(event.spotPrice.toString(), 18),
          );
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
        } else if (instanceOfSettle(event.config)) {
          await makeSettle(vault, deployer);
        }
      } else {
        console.log('Invalid event!!!');
      }
      await checkTotalAssetsLeakage(vault, deployer, asset);
    }
  }

  it('test event stream', async () => {
    await getNextMaturities();
    console.log('Set up vault.');
    const { callVault, deployer, base, quote, oracleAdapter, p } =
      await vaultSetup();
    console.log('Create signers.');
    let asset: ERC20Mock;
    if (await callVault.isCall()) {
      asset = base;
    } else {
      asset = quote;
    }
    await createSigners(asset);
    console.log('Set spot price maturities.');
    await setSpotPriceMaturities(base, quote, oracleAdapter);
    console.log('Create pools.');
    await createPools(deployer, base, quote, oracleAdapter, p);
    console.log('Create event stream.');
    const { events } = await createEventStream();
    console.log('Process events.');
    await processEvents(callVault, asset, deployer, oracleAdapter, events);
  });
});
