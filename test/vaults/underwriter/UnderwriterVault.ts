import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { now, ONE_DAY, increaseTo } from '../../../utils/time';
import { parseEther, parseUnits, formatEther } from 'ethers/lib/utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { bnToNumber } from '../../../utils/sdk/math';
import {
  addDeposit,
  deployer,
  caller,
  receiver,
  trader,
  vault,
  base,
  vaultSetup,
  oracleAdapter,
  quote,
  createPool,
  vaultProxy,
} from './VaultSetup';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { IPoolMock__factory, IPoolMock } from '../../../typechain';

describe('UnderwriterVault', () => {
  let startTime: number;
  let spot: number;
  let minMaturity: number;
  let maxMaturity: number;

  async function setMaturities() {
    startTime = await now();
    spot = 2800;
    minMaturity = startTime + 10 * ONE_DAY;
    maxMaturity = startTime + 20 * ONE_DAY;

    const infos = [
      {
        maturity: minMaturity.toString(),
        strikes: [],
        sizes: [],
      },
      {
        maturity: maxMaturity.toString(),
        strikes: [],
        sizes: [],
      },
    ];
    await vault.setListingsAndSizes(infos);
  }

  describe('#_getMaturityAfterTimestamp', () => {
    it('works for maturities with length 0', async () => {
      const { vault } = await loadFixture(vaultSetup);
      await expect(
        vault.getMaturityAfterTimestamp('50000'),
      ).to.be.revertedWithCustomError(vault, 'Vault__GreaterThanMaxMaturity');
    });

    it('works for maturities with length greater than 1', async () => {
      const infos = [
        {
          maturity: '100000',
          strikes: [],
          sizes: [],
        },
      ];
      await vault.setListingsAndSizes(infos);

      expect(infos[0]['maturity']).to.eq(
        await vault.getMaturityAfterTimestamp('50000'),
      );

      await vault.clearListingsAndSizes();
    });

    it('works for maturities with length greater than 1', async () => {
      const infos = [
        {
          maturity: '100000',
          strikes: [],
          sizes: [],
        },
        {
          maturity: '200000',
          strikes: [],
          sizes: [],
        },
        {
          maturity: '300000',
          strikes: [],
          sizes: [],
        },
      ];
      await vault.setListingsAndSizes(infos);

      expect(infos[0]['maturity']).to.eq(
        await vault.getMaturityAfterTimestamp('50000'),
      );
      expect(infos[1]['maturity']).to.eq(
        await vault.getMaturityAfterTimestamp('150000'),
      );
      expect(infos[2]['maturity']).to.eq(
        await vault.getMaturityAfterTimestamp('250000'),
      );

      await vault.clearListingsAndSizes();
    });
  });

  describe('#_getNumberOfUnexpiredListings', () => {
    let startTime = 100000;

    let t0 = startTime + 7 * ONE_DAY;
    let t1 = startTime + 10 * ONE_DAY;
    let t2 = startTime + 14 * ONE_DAY;
    let t3 = startTime + 30 * ONE_DAY;

    async function setup() {
      const { vault } = await loadFixture(vaultSetup);

      const infos = [
        {
          maturity: t0,
          strikes: [500, 1000, 1500, 2000].map((el) =>
            parseEther(el.toString()),
          ),
          sizes: [1, 1, 1, 1].map((el) => parseEther(el.toString())),
        },
        {
          maturity: t1,
          strikes: [1000, 1500, 2000].map((el) => parseEther(el.toString())),
          sizes: [1, 1, 1].map((el) => parseEther(el.toString())),
        },
        {
          maturity: t2,
          strikes: [1000, 1500, 2000].map((el) => parseEther(el.toString())),
          sizes: [1, 1, 1].map((el) => parseEther(el.toString())),
        },
        {
          maturity: 2 * t2,
          strikes: [1200, 1500].map((el) => parseEther(el.toString())),
          sizes: [1, 1].map((el) => parseEther(el.toString())),
        },
      ];
      await vault.setListingsAndSizes(infos);
    }

    let tests = [
      { timestamp: t0 - ONE_DAY, expected: 12 },
      { timestamp: t0, expected: 8 },
      { timestamp: t0 + ONE_DAY, expected: 8 },
      { timestamp: t2 + ONE_DAY, expected: 2 },
      { timestamp: t3, expected: 0 },
      { timestamp: t3 + ONE_DAY, expected: 0 },
    ];

    tests.forEach(async (test) => {
      it(`returns ${test.expected} when timestamp=${test.timestamp}`, async () => {
        await loadFixture(setup);
        let result = await vault.getNumberOfUnexpiredListings(test.timestamp);

        expect(result).to.eq(test.expected);
      });
    });

    it('returns 0 when there are no existing listings', async () => {
      await vault.clearListingsAndSizes();

      let result = await vault.getNumberOfUnexpiredListings(t0 - ONE_DAY);
      let expected = 0;

      expect(result).to.eq(expected);
    });
  });

  describe('#_getTotalFairValueExpired', () => {
    let startTime = 100000;

    let t0 = startTime + 7 * ONE_DAY;
    let t1 = startTime + 10 * ONE_DAY;
    let t2 = startTime + 14 * ONE_DAY;
    let t3 = startTime + 30 * ONE_DAY;

    before(async () => {
      const { vault } = await loadFixture(vaultSetup);

      await oracleAdapter.mock.quoteFrom
        .withArgs(base.address, quote.address, t0)
        .returns(parseUnits('1000', 18));
      await oracleAdapter.mock.quoteFrom
        .withArgs(base.address, quote.address, t1)
        .returns(parseUnits('1400', 18));
      await oracleAdapter.mock.quoteFrom
        .withArgs(base.address, quote.address, t2)
        .returns(parseUnits('1600', 18));
      await oracleAdapter.mock.quoteFrom
        .withArgs(base.address, quote.address, t3)
        .returns(parseUnits('1000', 18));

      const infos = [
        {
          maturity: t0,
          strikes: [800, 900, 1500, 2000].map((el) =>
            parseEther(el.toString()),
          ),
          sizes: [1, 2, 2, 1].map((el) => parseEther(el.toString())),
        },
        {
          maturity: t1,
          strikes: [700, 900, 1500].map((el) => parseEther(el.toString())),
          sizes: [1, 5, 1].map((el) => parseEther(el.toString())),
        },
        {
          maturity: t2,
          strikes: [800, 1500, 2000].map((el) => parseEther(el.toString())),
          sizes: [1, 2, 1].map((el) => parseEther(el.toString())),
        },
        {
          maturity: t3,
          strikes: [900, 1500].map((el) => parseEther(el.toString())),
          sizes: [2, 2].map((el) => parseEther(el.toString())),
        },
      ];
      await vault.setListingsAndSizes(infos);
    });

    let tests = [
      { isCall: true, timestamp: t0 - ONE_DAY, expected: 0 },
      { isCall: false, timestamp: t0 - ONE_DAY, expected: 0 },
      { isCall: true, timestamp: t0, expected: 0.4 },
      { isCall: false, timestamp: t0, expected: 2000 },
      { isCall: true, timestamp: t0 + ONE_DAY, expected: 0.4 },
      { isCall: false, timestamp: t0 + ONE_DAY, expected: 2000 },
      { isCall: true, timestamp: t1, expected: 0.4 + 2.28571428571 },
      { isCall: false, timestamp: t1, expected: 2000 + 100 },
      { isCall: true, timestamp: t1 + ONE_DAY, expected: 0.4 + 2.28571428571 },
      { isCall: false, timestamp: t1 + ONE_DAY, expected: 2000 + 100 },
      {
        isCall: true,
        timestamp: t2 + ONE_DAY,
        expected: 2.68571428571 + 0.625,
      },
      { isCall: false, timestamp: t2 + ONE_DAY, expected: 2100 + 400 },
      { isCall: true, timestamp: t3, expected: 2.68571428571 + 0.625 + 0.2 },
      { isCall: false, timestamp: t3, expected: 2100 + 400 + 1000 },
      {
        isCall: true,
        timestamp: t3 + ONE_DAY,
        expected: 2.68571428571 + 0.625 + 0.2,
      },
      { isCall: false, timestamp: t3 + ONE_DAY, expected: 2100 + 400 + 1000 },
    ];

    tests.forEach(async (test) => {
      it(`returns ${test.expected} when isCall=${test.isCall} and timestamp=${test.timestamp}`, async () => {
        await vault.setIsCall(test.isCall);
        let result = await vault.getTotalFairValueExpired(test.timestamp);
        let delta = test.isCall ? 0.00001 : 0.0;

        expect(parseFloat(formatEther(result))).to.be.closeTo(
          test.expected,
          delta,
        );
      });
    });

    it('returns 0 when there are no existing listings', async () => {
      await vault.clearListingsAndSizes();

      let result = await vault.getTotalFairValueExpired(t0 - ONE_DAY);
      let expected = 0;

      expect(result).to.eq(parseEther(expected.toString()));

      await vault.setIsCall(false);

      result = await vault.getTotalFairValueExpired(t0 - ONE_DAY);
      expected = 0;

      expect(result).to.eq(parseEther(expected.toString()));
    });
  });

  describe('#_getTotalFairValueUnexpired', () => {
    let startTime = 100000;

    let t0 = startTime + 7 * ONE_DAY;
    let t1 = startTime + 10 * ONE_DAY;
    let t2 = startTime + 14 * ONE_DAY;
    let t3 = startTime + 30 * ONE_DAY;
    let spot = parseEther('1000');

    before(async () => {
      const { vault } = await loadFixture(vaultSetup);
      const infos = [
        {
          maturity: t0,
          strikes: [800, 900, 1500, 2000].map((el) =>
            parseEther(el.toString()),
          ),
          sizes: [1, 2, 2, 1].map((el) => parseEther(el.toString())),
        },
        {
          maturity: t1,
          strikes: [700, 900, 1500].map((el) => parseEther(el.toString())),
          sizes: [1, 5, 1].map((el) => parseEther(el.toString())),
        },
        {
          maturity: t2,
          strikes: [800, 1500, 2000].map((el) => parseEther(el.toString())),
          sizes: [1, 2, 1].map((el) => parseEther(el.toString())),
        },
        {
          maturity: t3,
          strikes: [900, 1500].map((el) => parseEther(el.toString())),
          sizes: [2, 2].map((el) => parseEther(el.toString())),
        },
      ];
      await vault.setListingsAndSizes(infos);
    });

    let tests = [
      { isCall: true, timestamp: t0 - ONE_DAY, expected: 1.697282885495867 },
      { isCall: false, timestamp: t0 - ONE_DAY, expected: 5597.282885495868 },
      { isCall: true, timestamp: t0, expected: 1.2853079354050814 },
      { isCall: false, timestamp: t0, expected: 3585.3079354050824 },
      { isCall: true, timestamp: t0 + ONE_DAY, expected: 1.2755281851488665 },
      { isCall: false, timestamp: t0 + ONE_DAY, expected: 3575.528185148866 },
      { isCall: true, timestamp: t2 + ONE_DAY, expected: 0.24420148996961677 },
      { isCall: false, timestamp: t2 + ONE_DAY, expected: 1044.2014899696167 },
      { isCall: true, timestamp: t3, expected: 0 },
      { isCall: false, timestamp: t3, expected: 0 },
      { isCall: true, timestamp: t3 + ONE_DAY, expected: 0 },
      { isCall: false, timestamp: t3 + ONE_DAY, expected: 0 },
    ];

    tests.forEach(async (test) => {
      it(`returns ${test.expected} when isCall=${test.isCall} and timestamp=${test.timestamp}`, async () => {
        await vault.setIsCall(test.isCall);
        let result = await vault.getTotalFairValueUnexpired(
          test.timestamp,
          spot,
        );

        let delta = test.isCall ? 0.0001 : 0.01;

        expect(parseFloat(formatEther(result))).to.be.closeTo(
          test.expected,
          delta,
        );
      });
    });

    it('returns 0 when there are no existing listings', async () => {
      await vault.clearListingsAndSizes();

      let result = await vault.getTotalFairValueUnexpired(t0 - ONE_DAY, spot);
      let expected = 0;

      expect(result).to.eq(parseEther(expected.toString()));

      await vault.setIsCall(false);

      result = await vault.getTotalFairValueUnexpired(t0 - ONE_DAY, spot);
      expected = 0;

      expect(result).to.eq(parseEther(expected.toString()));
    });
  });

  describe('#_addListing', async () => {
    let startTime: number;
    let t0: number;
    let t1: number;
    let t2: number;
    before(async () => {
      const { vault } = await loadFixture(vaultSetup);

      startTime = await now();
      t0 = startTime + 7 * ONE_DAY;
      t1 = startTime + 10 * ONE_DAY;
      t2 = startTime + 14 * ONE_DAY;
    });

    it('adds a listing when there are no listings', async () => {
      let strike = parseEther('1000');
      let maturity = t1;

      let n = await vault.getNumberOfListings();
      expect(n).to.eq(0);

      await vault.addListing(strike, maturity);

      let c = await vault.contains(strike, maturity);

      expect(c).to.be.true;

      n = await vault.getNumberOfListings();
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(1);
      expect(minMaturity).to.eq(t1);
      expect(maxMaturity).to.eq(t1);
    });

    it('adds a listing to an existing maturity', async () => {
      let n = await vault.getNumberOfListings();
      expect(n).to.eq(1);

      let strike = parseEther('2000');
      let maturity = t1;

      await vault.addListing(strike, maturity);

      let c = await vault.contains(strike, maturity);

      expect(c).to.be.true;

      n = await vault.getNumberOfListings();
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(2);
      expect(minMaturity).to.eq(t1);
      expect(maxMaturity).to.eq(t1);
    });

    it('adds a listing with a maturity before minMaturity', async () => {
      let n = await vault.getNumberOfListings();
      expect(n).to.eq(2);

      let strike = parseEther('1000');
      let maturity = t0;

      await vault.addListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.true;

      n = await vault.getNumberOfListings();
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(3);
      expect(minMaturity).to.eq(t0);
      expect(maxMaturity).to.eq(t1);
    });

    it('adds a listing with a maturity after maxMaturity', async () => {
      let n = await vault.getNumberOfListings();
      expect(n).to.eq(3);

      let strike = parseEther('1000');
      let maturity = t2;

      await vault.addListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.true;

      n = await vault.getNumberOfListings();
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(4);
      expect(minMaturity).to.eq(t0);
      expect(maxMaturity).to.eq(t2);
    });

    it('will not add a duplicate listing', async () => {
      let n = await vault.getNumberOfListings();
      expect(n).to.eq(4);

      let strike = parseEther('1000');
      let maturity = t2;

      await vault.addListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.true;

      n = await vault.getNumberOfListings();
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(4);
      expect(minMaturity).to.eq(t0);
      expect(maxMaturity).to.eq(t2);
    });

    it('will not add a listing with a maturity that is expired', async () => {
      let strike = parseEther('1000');

      await expect(
        vault.addListing(strike, startTime),
      ).to.be.revertedWithCustomError(vault, 'Vault__OptionExpired');
    });
  });

  describe('#_removeListing', () => {
    let startTime = 100000;

    let t0 = startTime + 7 * ONE_DAY;
    let t1 = startTime + 10 * ONE_DAY;
    let t2 = startTime + 14 * ONE_DAY;

    before(async () => {
      const { vault } = await loadFixture(vaultSetup);

      const infos = [
        {
          maturity: t0,
          strikes: [1000, 2000].map((el) => parseEther(el.toString())),
          sizes: [0, 0].map((el) => parseEther(el.toString())),
        },
        {
          maturity: t1,
          strikes: [1000, 2000].map((el) => parseEther(el.toString())),
          sizes: [0, 0].map((el) => parseEther(el.toString())),
        },
        {
          maturity: t2,
          strikes: [1000].map((el) => parseEther(el.toString())),
          sizes: [0].map((el) => parseEther(el.toString())),
        },
      ];
      await vault.setListingsAndSizes(infos);
    });

    it('should adjust and remove maxMaturity when it becomes empty', async () => {
      let strike = parseEther('1000');
      let maturity = t2;

      let n = await vault.getNumberOfListings();
      expect(n).to.eq(5);

      await vault.removeListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.false;

      n = await vault.getNumberOfListingsOnMaturity(maturity);
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(0);
      expect(minMaturity).to.eq(t0);
      expect(maxMaturity).to.eq(t1);
    });

    it('should remove strike from minMaturity', async () => {
      let strike = parseEther('1000');
      let maturity = t0;

      let n = await vault.getNumberOfListings();
      expect(n).to.eq(4);

      await vault.removeListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.false;

      n = await vault.getNumberOfListingsOnMaturity(maturity);
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(1);
      expect(minMaturity).to.eq(t0);
      expect(maxMaturity).to.eq(t1);
    });

    it('should adjust and remove minMaturity when it becomes empty', async () => {
      let strike = parseEther('2000');
      let maturity = t0;

      let n = await vault.getNumberOfListings();
      expect(n).to.eq(3);

      await vault.removeListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.false;

      n = await vault.getNumberOfListingsOnMaturity(maturity);
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(0);
      expect(minMaturity).to.eq(t1);
      expect(maxMaturity).to.eq(t1);
    });

    it('should remove strike from single maturity', async () => {
      let strike = parseEther('1000');
      let maturity = t1;

      let n = await vault.getNumberOfListings();
      expect(n).to.eq(2);

      await vault.removeListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.false;

      n = await vault.getNumberOfListingsOnMaturity(maturity);
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(1);
      expect(minMaturity).to.eq(t1);
      expect(maxMaturity).to.eq(t1);
    });

    it('should remove strike from last maturity and leave 0 listings', async () => {
      let strike = parseEther('2000');
      let maturity = t1;

      let n = await vault.getNumberOfListings();
      expect(n).to.eq(1);

      await vault.removeListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.false;

      n = await vault.getNumberOfListingsOnMaturity(maturity);
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(0);
      expect(await vault.getNumberOfListings()).to.eq(0);
      expect(minMaturity).to.eq(0);
      expect(maxMaturity).to.eq(0);
    });
  });

  async function addTrade(
    trader: SignerWithAddress,
    maturity: number,
    strike: number,
    amount: number,
    tradeTime: number,
    spread: number,
  ) {
    // trade: buys 1 option contract, 0.5 premium, spread 0.1, maturity 10 (days), dte 10, strike 100
    const strikeParsed = await parseEther(strike.toString());
    const amountParsed = await parseEther(amount.toString());
    //
    await vault.insertStrike(minMaturity, strikeParsed);

    await vault.increaseTotalLockedSpread(parseEther(spread.toString()));
    const additionalSpreadRate = (spread / (maturity - tradeTime)) * 10 ** 18;
    const spreadRate = Math.trunc(additionalSpreadRate).toString();
    await vault.setLastSpreadUnlockUpdate(tradeTime);
    await vault.increaseSpreadUnlockingRate(spreadRate);
    await vault.increaseSpreadUnlockingTick(minMaturity, spreadRate);
    await vault.increaseTotalLockedAssets(amountParsed);
    // we assume that the premium is just the exercise value for now
    const premium: number = (spot - strike) / spot;
    await vault.increaseTotalAssets(parseEther(premium.toString()));
    await vault.increaseTotalAssets(parseEther(spread.toString()));
  }

  describe('#vault environment after a single trade', () => {
    it('setup Vault', async () => {
      const { vault } = await loadFixture(vaultSetup);
      await setMaturities();
      await addDeposit(vault.address, caller, 2);
      await addTrade(trader, minMaturity, 1000, 1, startTime, 0.1);
      console.log('Computing totalFairValue');
      console.log(await vault.getTotalFairValue());
      console.log('Computing pricePerShare');
      console.log(parseFloat(formatEther(await vault.getPricePerShare())));
      await increaseTo(minMaturity);
      console.log('Computing totalFairValue');
      console.log(await vault.getTotalFairValue());
      console.log('Computing totalLockedSpread');
      console.log(await vault.getTotalLockedSpread());
      console.log('Computing pricePerShare');
      console.log(parseFloat(formatEther(await vault.getPricePerShare())));
      await increaseTo(maxMaturity);
      console.log('Computing pricePerShare');
      console.log(parseFloat(formatEther(await vault.getPricePerShare())));
    });
  });

  describe('#convertToShares', () => {
    it('if no shares have been minted, minted shares should equal deposited assets', async () => {
      const { vault } = await loadFixture(vaultSetup);
      const assetAmount = parseEther('2');
      const shareAmount = await vault.convertToShares(assetAmount);
      expect(shareAmount).to.eq(assetAmount);
    });

    it('if supply is non-zero and pricePerShare is one, minted shares equals the deposited assets', async () => {
      const { vault } = await loadFixture(vaultSetup);
      await setMaturities();
      await addDeposit(vault.address, caller, 8, receiver);
      const assetAmount = parseEther('2');
      const shareAmount = await vault.convertToShares(assetAmount);
      expect(shareAmount).to.eq(assetAmount);
    });

    it('if supply is non-zero, minted shares equals the deposited assets adjusted by the pricePerShare', async () => {
      const { vault } = await loadFixture(vaultSetup);
      await setMaturities();
      await addDeposit(vault.address, caller, 2, receiver);
      await vault.increaseTotalLockedSpread(parseEther('1.0'));
      const assetAmount = 2;
      const shareAmount = await vault.convertToShares(
        parseEther(assetAmount.toString()),
      );
      expect(parseFloat(formatEther(shareAmount))).to.eq(2 * assetAmount);
    });
  });

  describe('#convertToAssets', () => {
    it('if total supply is zero, revert due to zero shares', async () => {
      const { vault } = await loadFixture(vaultSetup);
      const shareAmount = parseEther('2');
      await expect(
        vault.convertToAssets(shareAmount),
      ).to.be.revertedWithCustomError(vault, 'Vault__ZEROShares');
    });

    it('if supply is non-zero and pricePerShare is one, withdrawn assets equals share amount', async () => {
      await setMaturities();
      await addDeposit(vault.address, caller, 2, receiver);
      const shareAmount = parseEther('2');
      const assetAmount = await vault.convertToAssets(shareAmount);
      expect(shareAmount).to.eq(assetAmount);
    });

    it('if supply is non-zero and pricePerShare is 0.5, withdrawn assets equals half the share amount', async () => {
      const { vault } = await loadFixture(vaultSetup);
      await setMaturities();
      await addDeposit(vault.address, caller, 2, receiver);
      await vault.increaseTotalLockedSpread(parseEther('1.0'));
      const shareAmount = 2;
      const assetAmount = await vault.convertToAssets(
        parseEther(shareAmount.toString()),
      );
      expect(parseFloat(formatEther(assetAmount))).to.eq(0.5 * shareAmount);
    });
  });

  describe('#_availableAssets', () => {
    // availableAssets = totalAssets - totalLockedSpread - lockedAssets
    // totalAssets = totalDeposits + premiums + spread - exercise
    it('check formula for total available assets', async () => {
      const { vault } = await loadFixture(vaultSetup);
      await setMaturities();
      await addDeposit(vault.address, caller, 2, receiver);
      expect(await vault.getAvailableAssets()).to.eq(parseEther('2'));
      await vault.increaseTotalLockedSpread(parseEther('0.002'));
      expect(await vault.getAvailableAssets()).to.eq(parseEther('1.998'));
      await vault.increaseTotalLockedAssets(parseEther('0.5'));
      expect(await vault.getAvailableAssets()).to.eq(parseEther('1.498'));
      await vault.increaseTotalLockedSpread(parseEther('0.2'));
      expect(await vault.getAvailableAssets()).to.eq(parseEther('1.298'));
      await vault.increaseTotalLockedAssets(parseEther('0.0001'));
      expect(await vault.getAvailableAssets()).to.eq(parseEther('1.2979'));
    });
  });

  describe('#getPricePerShare', () => {
    let tests = [
      { expected: 1, deposit: 2, totalLockedSpread: 0, tradeSize: 0 },
      { expected: 0.9, deposit: 2, totalLockedSpread: 0.2, tradeSize: 0 },
      { expected: 0.98, deposit: 5, totalLockedSpread: 0.1, tradeSize: 0 },
      {
        expected: 0.56666666,
        deposit: 2,
        totalLockedSpread: 0.2,
        tradeSize: 1,
      },
      {
        expected: 0.66666666,
        deposit: 2,
        totalLockedSpread: 0,
        tradeSize: 1,
      },
    ];
    tests.forEach(async (test) => {
      it(`returns ${test.expected} when totalLockedSpread=${test.totalLockedSpread} and tradeSize=${test.tradeSize}`, async () => {
        const { vault } = await loadFixture(vaultSetup);
        // create a deposit and check that totalAssets and totalSupply amounts are computed correctly
        await addDeposit(vault.address, caller, test.deposit, receiver);
        let startTime = await now();
        let t0 = startTime + 7 * ONE_DAY;
        expect(await vault.totalAssets()).to.eq(
          parseEther(test.deposit.toString()),
        );
        expect(await vault.totalSupply()).to.eq(
          parseEther(test.deposit.toString()),
        );
        // mock vault
        await vault.increaseTotalLockedSpread(
          parseEther(test.totalLockedSpread.toString()),
        );
        await vault.setMaxMaturity(t0);
        if (test.tradeSize > 0) {
          const infos = [
            {
              maturity: t0,
              strikes: [500].map((el) => parseEther(el.toString())),
              sizes: [1].map((el) => parseEther(el.toString())),
            },
          ];
          await vault.setListingsAndSizes(infos);
        }
        let pps: number = parseFloat(
          formatEther(await vault.getPricePerShare()),
        );
        expect(pps).to.be.closeTo(test.expected, 0.00000001);
      });
    });
  });

  describe('#maxWithdraw', () => {
    it('maxWithdraw should revert for a zero address', async () => {
      const { vault } = await loadFixture(vaultSetup);
      await setMaturities();
      await addDeposit(vault.address, caller, 2, receiver);
      await expect(
        vault.maxWithdraw(ethers.constants.AddressZero),
      ).to.be.revertedWithCustomError(vault, 'Vault__AddressZero');
    });

    it('maxWithdraw should return the available assets for a non-zero address', async () => {
      const { vault } = await loadFixture(vaultSetup);
      await setMaturities();
      await addDeposit(vault.address, caller, 3, receiver);
      await vault.increaseTotalLockedSpread(parseEther('0.1'));
      await vault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = await vault.maxWithdraw(receiver.address);
      console.log(await vault.getPricePerShare());
      expect(assetAmount).to.eq(parseEther('2.4'));
    });

    it('maxWithdraw should return the assets the receiver owns', async () => {
      const { vault } = await loadFixture(vaultSetup);
      await setMaturities();
      await addDeposit(vault.address, caller, 8, caller);
      await addDeposit(vault.address, caller, 2, receiver);
      await vault.increaseTotalLockedSpread(parseEther('0.0'));
      await vault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = await vault.maxWithdraw(receiver.address);
      expect(assetAmount).to.eq(parseEther('2'));
    });

    it('maxWithdraw should return the assets the receiver owns since there are sufficient funds', async () => {
      const { vault } = await loadFixture(vaultSetup);
      await setMaturities();
      await addDeposit(vault.address, caller, 7, caller);
      await addDeposit(vault.address, caller, 2, receiver);
      await vault.increaseTotalLockedSpread(parseEther('0.1'));
      await vault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = parseFloat(
        formatEther(await vault.maxWithdraw(receiver.address)),
      );
      expect(assetAmount).to.be.closeTo(1.977777777777777, 0.00000001);
    });
  });

  describe('#maxRedeem', () => {
    it('maxRedeem should revert for a zero address', async () => {
      const { vault } = await loadFixture(vaultSetup);
      await setMaturities();
      await addDeposit(vault.address, caller, 2, receiver);
      await expect(
        vault.maxRedeem(ethers.constants.AddressZero),
      ).to.be.revertedWithCustomError(vault, 'Vault__AddressZero');
    });

    it('maxRedeem should return the amount of shares that are redeemable', async () => {
      const { vault } = await loadFixture(vaultSetup);
      await setMaturities();
      await addDeposit(vault.address, caller, 3, receiver);
      await vault.increaseTotalLockedSpread(parseEther('0.1'));
      await vault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = await vault.maxWithdraw(receiver.address);
      console.log(await vault.getPricePerShare());
      expect(assetAmount).to.eq(parseEther('2.4'));
    });
  });

  describe('#previewMint', () => {
    it('previewMint should return amount of assets required to mint the amount of shares', async () => {
      const { vault } = await loadFixture(vaultSetup);
      await setMaturities();
      const assetAmount = await vault.previewMint(parseEther('2.1'));
      expect(assetAmount).to.eq(parseEther('2.1'));
    });

    it('previewMint should return amount of assets required to mint', async () => {
      const { vault } = await loadFixture(vaultSetup);
      await setMaturities();
      await addDeposit(vault.address, caller, 2, receiver);
      await vault.increaseTotalLockedSpread(parseEther('0.2'));
      const assetAmount = await vault.previewMint(parseEther('4'));
      expect(assetAmount).to.eq(parseEther('3.6'));
    });
  });

  describe('#deposit', () => {
    it('deposit into an empty vault', async () => {
      const { vault } = await loadFixture(vaultSetup);
      const assetAmount = 2;
      const assetAmountEth = parseEther(assetAmount.toString());
      const baseBalanceCaller = await base.balanceOf(caller.address);
      const baseBalanceReceiver = await base.balanceOf(receiver.address);

      await addDeposit(vault.address, caller, assetAmount, receiver);

      expect(await base.balanceOf(vault.address)).to.eq(assetAmountEth);
      expect(await base.balanceOf(caller.address)).to.eq(
        baseBalanceCaller.sub(assetAmountEth),
      );
      expect(await base.balanceOf(receiver.address)).to.eq(baseBalanceReceiver);
      expect(await vault.balanceOf(caller.address)).to.eq(parseEther('0'));
      expect(await vault.balanceOf(receiver.address)).to.eq(assetAmountEth);
      expect(await vault.totalSupply()).to.eq(assetAmountEth);
    });

    it('deposit into a non-empty vault with a pricePerShare unequal to 1', async () => {
      const { vault } = await loadFixture(vaultSetup);
      await setMaturities();
      const two = 2;
      const four = 4;
      const twoFormatted = parseEther(two.toString());
      const fourFormatted = parseEther(four.toString());
      const baseBalanceCaller = await base.balanceOf(caller.address);
      const baseBalanceReceiver = await base.balanceOf(receiver.address);
      await addDeposit(vault.address, caller, two, receiver);

      // modify the price per share to (2 - 0.5) / 2 = 0.75
      await vault
        .connect(deployer)
        .increaseTotalLockedSpread(parseEther('0.5'));
      await addDeposit(vault.address, caller, two, receiver);

      expect(await base.balanceOf(vault.address)).to.eq(fourFormatted);
      expect(await base.balanceOf(caller.address)).to.eq(
        baseBalanceCaller.sub(fourFormatted),
      );
      expect(await base.balanceOf(receiver.address)).to.eq(baseBalanceReceiver);
      expect(await vault.balanceOf(caller.address)).to.eq(parseEther('0'));
      expect(
        parseFloat(formatEther(await vault.balanceOf(receiver.address))),
      ).to.be.closeTo(2 + 2 / 0.75, 0.00001);
    });

    /*
    // TODO: fix test
    it('revert when receiver has zero address', async () => {
      const { vault } = await loadFixture(vaultSetup);
      setupVault();
      const assetAmount = parseEther('2');
      await base.connect(caller).approve(vault.address, assetAmount);
      await vault.connect(caller).deposit(assetAmount, receiver.address);
      await expect(
        vault
          .connect(caller)
          .deposit(assetAmount, ethers.constants.AddressZero),
      ).to.be.revertedWith('ERC20Base__MintToZeroAddress');
    });
     */
  });

  describe('#afterBuy', () => {
    const premium = 0.5;
    const spread = 0.1;
    const size = 1;
    const strike = 100;
    let maturity: number;
    let totalAssets: number;
    let spreadUnlockingRate: number;
    let afterBuyTimestamp: number;

    async function setupAfterBuyVault(isCall: boolean) {
      const { vault } = await loadFixture(vaultSetup);
      await setMaturities();
      await vault.setIsCall(isCall);
      totalAssets = parseFloat(formatEther(await vault.totalAssets()));
      console.log('Setup vault.');

      maturity = minMaturity;
      spreadUnlockingRate = spread / (minMaturity - startTime);

      await vault.afterBuy(
        minMaturity,
        parseEther(premium.toString()),
        maturity - startTime,
        parseEther(size.toString()),
        parseEther(spread.toString()),
        parseEther(strike.toString()),
      );
      afterBuyTimestamp = await now();
      console.log('Processed afterBuy.');
      return { vault };
    }

    it('lastSpreadUnlockUpdate should equal the time we executed afterBuy as we updated the state there', async () => {
      const { vault } = await setupAfterBuyVault(true);
      expect(await vault.lastSpreadUnlockUpdate()).to.eq(afterBuyTimestamp);
    });

    it('spreadUnlockingRates should equal', async () => {
      expect(
        parseFloat(formatEther(await vault.spreadUnlockingRate())),
      ).to.be.closeTo(spreadUnlockingRate, 0.000000000000000001);
    });

    it('total assets should equal', async () => {
      expect(parseFloat(formatEther(await vault.totalAssets()))).to.eq(
        totalAssets + premium + spread,
      );
    });

    it('positionSize should equal ', async () => {
      const positionSize = await vault.positionSize(
        maturity,
        parseEther(strike.toString()),
      );
      expect(parseFloat(formatEther(positionSize))).to.eq(size);
    });

    it('spreadUnlockingRate / ticks', async () => {
      expect(
        parseFloat(formatEther(await vault.spreadUnlockingTicks(maturity))),
      ).to.be.closeTo(spreadUnlockingRate, 0.000000000000000001);
    });

    it('totalLockedSpread should equa', async () => {
      expect(parseFloat(formatEther(await vault.totalLockedSpread()))).to.eq(
        spread,
      );
    });

    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('totalLockedAssets should equal', async () => {
          const { vault } = await setupAfterBuyVault(isCall);
          const totalLocked = isCall ? size : size * strike;
          expect(
            parseFloat(formatEther(await vault.totalLockedAssets())),
          ).to.eq(totalLocked);
        });
      });
    }
  });

  describe('#settleMaturity', () => {
    it('test settling an option', async () => {
      const { vault, deployer, base, quote, oracleAdapter, p } =
        await vaultSetup();
      await addDeposit(vault.address, caller, 4);

      const strike = parseEther('1000');
      const maturity = 1677830400;
      const size = parseEther('1');
      const isCall = true;

      await createPool(
        strike,
        maturity,
        isCall,
        deployer,
        base,
        quote,
        oracleAdapter,
        p,
      );

      await vault.connect(caller).mintFromPool(strike, maturity, size);
      //await callPool.balanceOf()
    });
  });

  describe('#settle', () => {});

  describe('test getTotalLockedSpread and updateState', () => {
    /*
    Example

    |-----t0---t1-----t2---|

    Time to maturities starting from inception
    ---------------
    t0: 7 days
    t1: 10 days
    t2: 14 days

    Spread locked at inception
    ---------------
    t0: 1.24
    t1: 5.56
    t2: 11.2

    initial spreadUnlockingRate: (1.24 / 7 + 5.56 / 10 + 11.2 / 14) / (24 * 60 * 60)

    */
    let startTime: number;
    let t0: number;
    let t1: number;
    let t2: number;
    let spreadUnlockingRatet0: number;
    let spreadUnlockingRatet1: number;
    let spreadUnlockingRatet2: number;
    let spreadUnlockingRate: number;

    async function setupSpreadsVault() {
      const { vault } = await loadFixture(vaultSetup);
      startTime = await now();
      t0 = startTime + 7 * ONE_DAY;
      t1 = startTime + 10 * ONE_DAY;
      t2 = startTime + 14 * ONE_DAY;
      console.log('startTime', startTime);
      console.log('t0', t0);
      console.log('t1', t1);
      console.log('t2', t2);

      const infos = [
        {
          maturity: t0,
          strikes: [],
          sizes: [],
        },
        {
          maturity: t1,
          strikes: [],
          sizes: [],
        },
        {
          maturity: t2,
          strikes: [],
          sizes: [],
        },
        {
          maturity: 2 * t2,
          strikes: [],
          sizes: [],
        },
      ];
      await vault.setListingsAndSizes(infos);
      await vault.setLastSpreadUnlockUpdate(startTime);
      const totalLockedSpread = 1.24 + 5.56 + 11.2;
      console.log('totalLockedSpread', totalLockedSpread);
      const totalLockedFormatted = parseEther(totalLockedSpread.toString());
      spreadUnlockingRatet0 = 1.24 / (7 * ONE_DAY);
      spreadUnlockingRatet1 = 5.56 / (10 * ONE_DAY);
      spreadUnlockingRatet2 = 11.2 / (14 * ONE_DAY);
      const surt0 = parseEther(spreadUnlockingRatet0.toFixed(18).toString());
      const surt1 = parseEther(spreadUnlockingRatet1.toFixed(18).toString());
      const surt2 = parseEther(spreadUnlockingRatet2.toFixed(18).toString());

      console.log(spreadUnlockingRatet0);
      console.log(spreadUnlockingRatet1);
      console.log(spreadUnlockingRatet2);
      console.log(parseEther(spreadUnlockingRatet0.toFixed(18).toString()));
      console.log(parseEther(spreadUnlockingRatet1.toFixed(18).toString()));
      console.log(parseEther(spreadUnlockingRatet2.toFixed(18).toString()));

      await vault.increaseSpreadUnlockingTick(t0, surt0);
      await vault.increaseSpreadUnlockingTick(t1, surt1);
      await vault.increaseSpreadUnlockingTick(t2, surt2);
      spreadUnlockingRate =
        spreadUnlockingRatet0 + spreadUnlockingRatet1 + spreadUnlockingRatet2;
      await vault.increaseSpreadUnlockingRate(
        parseEther(spreadUnlockingRate.toFixed(18).toString()),
      );
      await vault.increaseTotalLockedSpread(totalLockedFormatted);
    }

    describe('#getTotalLockedSpread', () => {
      it('At startTime + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        await loadFixture(setupSpreadsVault);
        await increaseTo(startTime + ONE_DAY);
        expect(
          parseFloat(formatEther(await vault.getTotalLockedSpread())),
        ).to.be.closeTo(16.4668, 0.001);
      });

      it('At maturity t0 totalLockedSpread should approximately equal 7.268', async () => {
        // 7 / 14 * 11.2 + 3 / 10 * 5.56 = 7.268
        await increaseTo(t0);
        expect(
          parseFloat(formatEther(await vault.getTotalLockedSpread())),
        ).to.be.closeTo(7.268, 0.001);
      });

      it('At t0 + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        // 6 / 14 * 11.2 + 2 / 10 * 5.56 = 5.912
        await increaseTo(t0 + ONE_DAY);
        expect(
          parseFloat(formatEther(await vault.getTotalLockedSpread())),
        ).to.be.closeTo(5.912, 0.001);
      });

      it('At maturity t1 totalLockedSpread should approximately equal 3.2', async () => {
        // 11.2 * 3 / 14 = 3.2
        await increaseTo(t1);
        expect(
          parseFloat(formatEther(await vault.getTotalLockedSpread())),
        ).to.be.closeTo(3.2, 0.001);
      });

      it('At t1 + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        // 3 / 14 * 11.2 = 2.4
        await increaseTo(t1 + ONE_DAY);
        expect(
          parseFloat(formatEther(await vault.getTotalLockedSpread())),
        ).to.be.closeTo(2.4, 0.001);
      });

      it('At maturity t2 totalLockedSpread should approximately equal 0.0', async () => {
        // 0
        await increaseTo(t2);
        expect(
          parseFloat(formatEther(await vault.getTotalLockedSpread())),
        ).to.be.closeTo(0.0, 0.0000001);
      });

      it('At maturity t2 + 7 days totalLockedSpread should approximately equal 0.0', async () => {
        // 0
        await increaseTo(t0 + 7 * ONE_DAY);
        expect(
          parseFloat(formatEther(await vault.getTotalLockedSpread())),
        ).to.be.closeTo(0.0, 0.0000001);
      });
    });

    describe('#updateState', () => {
      it('At startTime + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        await loadFixture(setupSpreadsVault);
        await increaseTo(startTime + ONE_DAY);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(16.4668, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await now());
      });

      it('At maturity t0 totalLockedSpread should approximately equal 7.268', async () => {
        // 7 / 14 * 11.2 + 3 / 10 * 5.56 = 7.268
        await loadFixture(setupSpreadsVault);
        await increaseTo(t0);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(7.268, 0.001);
        spreadUnlockingRate = spreadUnlockingRatet1 + spreadUnlockingRatet2;
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);

        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await now());
      });

      it('At t0 + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        // 6 / 14 * 11.2 + 2 / 10 * 5.56 = 5.912
        await loadFixture(setupSpreadsVault);
        await increaseTo(t0 + ONE_DAY);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(5.912, 0.001);
        spreadUnlockingRate = spreadUnlockingRatet1 + spreadUnlockingRatet2;
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await now());
      });

      it('At maturity t1 totalLockedSpread should approximately equal 3.2', async () => {
        // 11.2 * 3 / 14 = 3.2
        await loadFixture(setupSpreadsVault);
        await increaseTo(t1);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(3.2, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRatet2, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await now());
      });

      it('At t1 + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        // 3 / 14 * 11.2 = 2.4
        await loadFixture(setupSpreadsVault);
        await increaseTo(t1 + ONE_DAY);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(2.4, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRatet2, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await now());
      });

      it('At maturity t2 totalLockedSpread should approximately equal 0.0', async () => {
        await loadFixture(setupSpreadsVault);
        await increaseTo(t2);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(0.0, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(0.0, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await now());
      });

      it('Run through all of the above', async () => {
        await loadFixture(setupSpreadsVault);
        await increaseTo(startTime + ONE_DAY);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(16.4668, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await now());
        await increaseTo(t0);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(7.268, 0.001);
        spreadUnlockingRate = spreadUnlockingRatet1 + spreadUnlockingRatet2;
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);

        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await now());
        await increaseTo(t0 + ONE_DAY);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(5.912, 0.001);
        spreadUnlockingRate = spreadUnlockingRatet1 + spreadUnlockingRatet2;
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await now());
        await increaseTo(t1);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(3.2, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRatet2, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await now());
        await increaseTo(t1 + ONE_DAY);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(2.4, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRatet2, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await now());
        await increaseTo(t2);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(0.0, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(0.0, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await now());
      });
    });
  });
});
