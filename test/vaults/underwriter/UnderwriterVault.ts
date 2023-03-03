import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import {
  now,
  ONE_DAY,
  ONE_HOUR,
  ONE_WEEK,
  increaseTo,
} from '../../../utils/time';
import { parseEther, parseUnits, formatEther } from 'ethers/lib/utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { bnToNumber } from '../../../utils/sdk/math';
import {
  addDeposit,
  deployer,
  caller,
  receiver,
  trader,
  callVault,
  base,
  vaultSetup,
  oracleAdapter,
  quote,
  createPool,
  vaultProxy,
  putVault,
} from './VaultSetup';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  IPoolMock__factory,
  IPoolMock,
  UnderwriterVaultMock,
} from '../../../typechain';
import { parse } from 'path';

describe('UnderwriterVault', () => {
  let startTime: number;
  let spot: number;
  let minMaturity: number;
  let maxMaturity: number;

  async function setMaturities(vault: UnderwriterVaultMock) {
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
      const { callVault } = await loadFixture(vaultSetup);
      await expect(
        callVault.getMaturityAfterTimestamp('50000'),
      ).to.be.revertedWithCustomError(
        callVault,
        'Vault__GreaterThanMaxMaturity',
      );
    });

    it('works for maturities with length greater than 1', async () => {
      const infos = [
        {
          maturity: '100000',
          strikes: [],
          sizes: [],
        },
      ];
      await callVault.setListingsAndSizes(infos);

      expect(infos[0]['maturity']).to.eq(
        await callVault.getMaturityAfterTimestamp('50000'),
      );

      await callVault.clearListingsAndSizes();
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
      await callVault.setListingsAndSizes(infos);

      expect(infos[0]['maturity']).to.eq(
        await callVault.getMaturityAfterTimestamp('50000'),
      );
      expect(infos[1]['maturity']).to.eq(
        await callVault.getMaturityAfterTimestamp('150000'),
      );
      expect(infos[2]['maturity']).to.eq(
        await callVault.getMaturityAfterTimestamp('250000'),
      );

      await callVault.clearListingsAndSizes();
    });
  });

  describe('#_getNumberOfUnexpiredListings', () => {
    let startTime = 100000;

    let t0 = startTime + 7 * ONE_DAY;
    let t1 = startTime + 10 * ONE_DAY;
    let t2 = startTime + 14 * ONE_DAY;
    let t3 = startTime + 30 * ONE_DAY;

    async function setup() {
      const { callVault } = await loadFixture(vaultSetup);

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
      await callVault.setListingsAndSizes(infos);
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
        let result = await callVault.getNumberOfUnexpiredListings(
          test.timestamp,
        );

        expect(result).to.eq(test.expected);
      });
    });

    it('returns 0 when there are no existing listings', async () => {
      await callVault.clearListingsAndSizes();

      let result = await callVault.getNumberOfUnexpiredListings(t0 - ONE_DAY);
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
      const { callVault } = await loadFixture(vaultSetup);

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
      await callVault.setListingsAndSizes(infos);
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
        await callVault.setIsCall(test.isCall);
        let result = await callVault.getTotalFairValueExpired(test.timestamp);
        let delta = test.isCall ? 0.00001 : 0.0;

        expect(parseFloat(formatEther(result))).to.be.closeTo(
          test.expected,
          delta,
        );
      });
    });

    it('returns 0 when there are no existing listings', async () => {
      await callVault.clearListingsAndSizes();

      let result = await callVault.getTotalFairValueExpired(t0 - ONE_DAY);
      let expected = 0;

      expect(result).to.eq(parseEther(expected.toString()));

      await callVault.setIsCall(false);

      result = await callVault.getTotalFairValueExpired(t0 - ONE_DAY);
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
      const { callVault } = await loadFixture(vaultSetup);
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
      await callVault.setListingsAndSizes(infos);
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
        await callVault.setIsCall(test.isCall);
        let result = await callVault.getTotalFairValueUnexpired(
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
      await callVault.clearListingsAndSizes();

      let result = await callVault.getTotalFairValueUnexpired(
        t0 - ONE_DAY,
        spot,
      );
      let expected = 0;

      expect(result).to.eq(parseEther(expected.toString()));

      await callVault.setIsCall(false);

      result = await callVault.getTotalFairValueUnexpired(t0 - ONE_DAY, spot);
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
      const { callVault } = await loadFixture(vaultSetup);

      startTime = await now();
      t0 = startTime + 7 * ONE_DAY;
      t1 = startTime + 10 * ONE_DAY;
      t2 = startTime + 14 * ONE_DAY;
    });

    it('adds a listing when there are no listings', async () => {
      let strike = parseEther('1000');
      let maturity = t1;

      let n = await callVault.getNumberOfListings();
      expect(n).to.eq(0);

      await callVault.addListing(strike, maturity);

      let c = await callVault.contains(strike, maturity);

      expect(c).to.be.true;

      n = await callVault.getNumberOfListings();
      let minMaturity = await callVault.getMinMaturity();
      let maxMaturity = await callVault.getMaxMaturity();

      expect(n).to.eq(1);
      expect(minMaturity).to.eq(t1);
      expect(maxMaturity).to.eq(t1);
    });

    it('adds a listing to an existing maturity', async () => {
      let n = await callVault.getNumberOfListings();
      expect(n).to.eq(1);

      let strike = parseEther('2000');
      let maturity = t1;

      await callVault.addListing(strike, maturity);

      let c = await callVault.contains(strike, maturity);

      expect(c).to.be.true;

      n = await callVault.getNumberOfListings();
      let minMaturity = await callVault.getMinMaturity();
      let maxMaturity = await callVault.getMaxMaturity();

      expect(n).to.eq(2);
      expect(minMaturity).to.eq(t1);
      expect(maxMaturity).to.eq(t1);
    });

    it('adds a listing with a maturity before minMaturity', async () => {
      let n = await callVault.getNumberOfListings();
      expect(n).to.eq(2);

      let strike = parseEther('1000');
      let maturity = t0;

      await callVault.addListing(strike, maturity);

      let c = await callVault.contains(strike, maturity);
      expect(c).to.be.true;

      n = await callVault.getNumberOfListings();
      let minMaturity = await callVault.getMinMaturity();
      let maxMaturity = await callVault.getMaxMaturity();

      expect(n).to.eq(3);
      expect(minMaturity).to.eq(t0);
      expect(maxMaturity).to.eq(t1);
    });

    it('adds a listing with a maturity after maxMaturity', async () => {
      let n = await callVault.getNumberOfListings();
      expect(n).to.eq(3);

      let strike = parseEther('1000');
      let maturity = t2;

      await callVault.addListing(strike, maturity);

      let c = await callVault.contains(strike, maturity);
      expect(c).to.be.true;

      n = await callVault.getNumberOfListings();
      let minMaturity = await callVault.getMinMaturity();
      let maxMaturity = await callVault.getMaxMaturity();

      expect(n).to.eq(4);
      expect(minMaturity).to.eq(t0);
      expect(maxMaturity).to.eq(t2);
    });

    it('will not add a duplicate listing', async () => {
      let n = await callVault.getNumberOfListings();
      expect(n).to.eq(4);

      let strike = parseEther('1000');
      let maturity = t2;

      await callVault.addListing(strike, maturity);

      let c = await callVault.contains(strike, maturity);
      expect(c).to.be.true;

      n = await callVault.getNumberOfListings();
      let minMaturity = await callVault.getMinMaturity();
      let maxMaturity = await callVault.getMaxMaturity();

      expect(n).to.eq(4);
      expect(minMaturity).to.eq(t0);
      expect(maxMaturity).to.eq(t2);
    });

    it('will not add a listing with a maturity that is expired', async () => {
      let strike = parseEther('1000');

      await expect(
        callVault.addListing(strike, startTime),
      ).to.be.revertedWithCustomError(callVault, 'Vault__OptionExpired');
    });
  });

  describe('#_removeListing', () => {
    let startTime = 100000;

    let t0 = startTime + 7 * ONE_DAY;
    let t1 = startTime + 10 * ONE_DAY;
    let t2 = startTime + 14 * ONE_DAY;

    before(async () => {
      const { callVault } = await loadFixture(vaultSetup);

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
      await callVault.setListingsAndSizes(infos);
    });

    it('should adjust and remove maxMaturity when it becomes empty', async () => {
      let strike = parseEther('1000');
      let maturity = t2;

      let n = await callVault.getNumberOfListings();
      expect(n).to.eq(5);

      await callVault.removeListing(strike, maturity);

      let c = await callVault.contains(strike, maturity);
      expect(c).to.be.false;

      n = await callVault.getNumberOfListingsOnMaturity(maturity);
      let minMaturity = await callVault.getMinMaturity();
      let maxMaturity = await callVault.getMaxMaturity();

      expect(n).to.eq(0);
      expect(minMaturity).to.eq(t0);
      expect(maxMaturity).to.eq(t1);
    });

    it('should remove strike from minMaturity', async () => {
      let strike = parseEther('1000');
      let maturity = t0;

      let n = await callVault.getNumberOfListings();
      expect(n).to.eq(4);

      await callVault.removeListing(strike, maturity);

      let c = await callVault.contains(strike, maturity);
      expect(c).to.be.false;

      n = await callVault.getNumberOfListingsOnMaturity(maturity);
      let minMaturity = await callVault.getMinMaturity();
      let maxMaturity = await callVault.getMaxMaturity();

      expect(n).to.eq(1);
      expect(minMaturity).to.eq(t0);
      expect(maxMaturity).to.eq(t1);
    });

    it('should adjust and remove minMaturity when it becomes empty', async () => {
      let strike = parseEther('2000');
      let maturity = t0;

      let n = await callVault.getNumberOfListings();
      expect(n).to.eq(3);

      await callVault.removeListing(strike, maturity);

      let c = await callVault.contains(strike, maturity);
      expect(c).to.be.false;

      n = await callVault.getNumberOfListingsOnMaturity(maturity);
      let minMaturity = await callVault.getMinMaturity();
      let maxMaturity = await callVault.getMaxMaturity();

      expect(n).to.eq(0);
      expect(minMaturity).to.eq(t1);
      expect(maxMaturity).to.eq(t1);
    });

    it('should remove strike from single maturity', async () => {
      let strike = parseEther('1000');
      let maturity = t1;

      let n = await callVault.getNumberOfListings();
      expect(n).to.eq(2);

      await callVault.removeListing(strike, maturity);

      let c = await callVault.contains(strike, maturity);
      expect(c).to.be.false;

      n = await callVault.getNumberOfListingsOnMaturity(maturity);
      let minMaturity = await callVault.getMinMaturity();
      let maxMaturity = await callVault.getMaxMaturity();

      expect(n).to.eq(1);
      expect(minMaturity).to.eq(t1);
      expect(maxMaturity).to.eq(t1);
    });

    it('should remove strike from last maturity and leave 0 listings', async () => {
      let strike = parseEther('2000');
      let maturity = t1;

      let n = await callVault.getNumberOfListings();
      expect(n).to.eq(1);

      await callVault.removeListing(strike, maturity);

      let c = await callVault.contains(strike, maturity);
      expect(c).to.be.false;

      n = await callVault.getNumberOfListingsOnMaturity(maturity);
      let minMaturity = await callVault.getMinMaturity();
      let maxMaturity = await callVault.getMaxMaturity();

      expect(n).to.eq(0);
      expect(await callVault.getNumberOfListings()).to.eq(0);
      expect(minMaturity).to.eq(0);
      expect(maxMaturity).to.eq(0);
    });
  });

  describe('#convertToShares', () => {
    it('if no shares have been minted, minted shares should equal deposited assets', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      const assetAmount = parseEther('2');
      const shareAmount = await callVault.convertToShares(assetAmount);
      expect(shareAmount).to.eq(assetAmount);
    });

    it('if supply is non-zero and pricePerShare is one, minted shares equals the deposited assets', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      await addDeposit(callVault, caller, 8, base, quote, receiver);
      const assetAmount = parseEther('2');
      const shareAmount = await callVault.convertToShares(assetAmount);
      expect(shareAmount).to.eq(assetAmount);
    });

    it('if supply is non-zero, minted shares equals the deposited assets adjusted by the pricePerShare', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      await addDeposit(callVault, caller, 2, base, quote, receiver);
      await callVault.increaseTotalLockedSpread(parseEther('1.0'));
      const assetAmount = 2;
      const shareAmount = await callVault.convertToShares(
        parseEther(assetAmount.toString()),
      );
      expect(parseFloat(formatEther(shareAmount))).to.eq(2 * assetAmount);
    });
  });

  describe('#convertToAssets', () => {
    it('if total supply is zero, revert due to zero shares', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      const shareAmount = parseEther('2');
      await expect(
        callVault.convertToAssets(shareAmount),
      ).to.be.revertedWithCustomError(callVault, 'Vault__ZEROShares');
    });

    it('if supply is non-zero and pricePerShare is one, withdrawn assets equals share amount', async () => {
      await setMaturities(callVault);
      await addDeposit(callVault, caller, 2, base, quote, receiver);
      const shareAmount = parseEther('2');
      const assetAmount = await callVault.convertToAssets(shareAmount);
      expect(shareAmount).to.eq(assetAmount);
    });

    it('if supply is non-zero and pricePerShare is 0.5, withdrawn assets equals half the share amount', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      await addDeposit(callVault, caller, 2, base, quote, receiver);
      await callVault.increaseTotalLockedSpread(parseEther('1.0'));
      const shareAmount = 2;
      const assetAmount = await callVault.convertToAssets(
        parseEther(shareAmount.toString()),
      );
      expect(parseFloat(formatEther(assetAmount))).to.eq(0.5 * shareAmount);
    });
  });

  describe('#_availableAssets', () => {
    // availableAssets = totalAssets - totalLockedSpread - lockedAssets
    // totalAssets = totalDeposits + premiums + spread - exercise
    it('check formula for total available assets', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      await addDeposit(callVault, caller, 2, base, quote, receiver);
      expect(await callVault.getAvailableAssets()).to.eq(parseEther('2'));
      await callVault.increaseTotalLockedSpread(parseEther('0.002'));
      expect(await callVault.getAvailableAssets()).to.eq(parseEther('1.998'));
      await callVault.increaseTotalLockedAssets(parseEther('0.5'));
      expect(await callVault.getAvailableAssets()).to.eq(parseEther('1.498'));
      await callVault.increaseTotalLockedSpread(parseEther('0.2'));
      expect(await callVault.getAvailableAssets()).to.eq(parseEther('1.298'));
      await callVault.increaseTotalLockedAssets(parseEther('0.0001'));
      expect(await callVault.getAvailableAssets()).to.eq(parseEther('1.2979'));
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
        const { callVault } = await loadFixture(vaultSetup);
        // create a deposit and check that totalAssets and totalSupply amounts are computed correctly
        await addDeposit(
          callVault,
          caller,
          test.deposit,
          base,
          quote,
          receiver,
        );
        let startTime = await now();
        let t0 = startTime + 7 * ONE_DAY;
        expect(await callVault.totalAssets()).to.eq(
          parseEther(test.deposit.toString()),
        );
        expect(await callVault.totalSupply()).to.eq(
          parseEther(test.deposit.toString()),
        );
        // mock vault
        await callVault.increaseTotalLockedSpread(
          parseEther(test.totalLockedSpread.toString()),
        );
        await callVault.setMaxMaturity(t0);
        if (test.tradeSize > 0) {
          const infos = [
            {
              maturity: t0,
              strikes: [500].map((el) => parseEther(el.toString())),
              sizes: [1].map((el) => parseEther(el.toString())),
            },
          ];
          await callVault.setListingsAndSizes(infos);
        }
        let pps: number = parseFloat(
          formatEther(await callVault.getPricePerShare()),
        );
        expect(pps).to.be.closeTo(test.expected, 0.00000001);
      });
    });
  });

  describe('#maxWithdraw', () => {
    it('maxWithdraw should revert for a zero address', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      await addDeposit(callVault, caller, 2, base, quote, receiver);
      await expect(
        callVault.maxWithdraw(ethers.constants.AddressZero),
      ).to.be.revertedWithCustomError(callVault, 'Vault__AddressZero');
    });

    it('maxWithdraw should return the available assets for a non-zero address', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      await addDeposit(callVault, caller, 3, base, quote, receiver);
      await callVault.increaseTotalLockedSpread(parseEther('0.1'));
      await callVault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = await callVault.maxWithdraw(receiver.address);
      console.log(await callVault.getPricePerShare());
      expect(assetAmount).to.eq(parseEther('2.4'));
    });

    it('maxWithdraw should return the assets the receiver owns', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      await addDeposit(callVault, caller, 8, base, quote, caller);
      await addDeposit(callVault, caller, 2, base, quote, receiver);
      await callVault.increaseTotalLockedSpread(parseEther('0.0'));
      await callVault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = await callVault.maxWithdraw(receiver.address);
      expect(assetAmount).to.eq(parseEther('2'));
    });

    it('maxWithdraw should return the assets the receiver owns since there are sufficient funds', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      await addDeposit(callVault, caller, 7, base, quote, caller);
      await addDeposit(callVault, caller, 2, base, quote, receiver);
      await callVault.increaseTotalLockedSpread(parseEther('0.1'));
      await callVault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = parseFloat(
        formatEther(await callVault.maxWithdraw(receiver.address)),
      );
      expect(assetAmount).to.be.closeTo(1.977777777777777, 0.00000001);
    });
  });

  describe('#maxRedeem', () => {
    it('maxRedeem should revert for a zero address', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      await addDeposit(callVault, caller, 2, base, quote, receiver);
      await expect(
        callVault.maxRedeem(ethers.constants.AddressZero),
      ).to.be.revertedWithCustomError(callVault, 'Vault__AddressZero');
    });

    it('maxRedeem should return the amount of shares that are redeemable', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      await addDeposit(callVault, caller, 3, base, quote, receiver);
      await callVault.increaseTotalLockedSpread(parseEther('0.1'));
      await callVault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = await callVault.maxWithdraw(receiver.address);
      console.log(await callVault.getPricePerShare());
      expect(assetAmount).to.eq(parseEther('2.4'));
    });
  });

  describe('#previewMint', () => {
    it('previewMint should return amount of assets required to mint the amount of shares', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      const assetAmount = await callVault.previewMint(parseEther('2.1'));
      expect(assetAmount).to.eq(parseEther('2.1'));
    });

    it('previewMint should return amount of assets required to mint', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      await addDeposit(callVault, caller, 2, base, quote, receiver);
      await callVault.increaseTotalLockedSpread(parseEther('0.2'));
      const assetAmount = await callVault.previewMint(parseEther('4'));
      expect(assetAmount).to.eq(parseEther('3.6'));
    });
  });

  describe('#deposit', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        describe('deposit into an empty vault', () => {
          let asset: any;
          let vault: UnderwriterVaultMock;
          let assetAmount = 2;
          let assetAmountEth: BigNumber;
          let balanceCaller: BigNumber;
          let balanceReceiver: BigNumber;
          beforeEach(async () => {
            const { callVault, putVault, base, quote } = await loadFixture(
              vaultSetup,
            );

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

            await addDeposit(
              vault,
              caller,
              assetAmount,
              asset,
              quote,
              receiver,
            );
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
            expect(await vault.balanceOf(caller.address)).to.eq(
              parseEther('0'),
            );
          });
          it('receiver should have received the outstanding shares', async () => {
            expect(await vault.balanceOf(receiver.address)).to.eq(
              assetAmountEth,
            );
          });
          it('total supply of the the vault should have increased by the asset amount ', async () => {
            expect(await vault.totalSupply()).to.eq(assetAmountEth);
          });
        });

        describe('deposit into a non-empty vault with a pricePerShare unequal to 1', () => {
          let asset: any;
          let vault: UnderwriterVaultMock;
          let assetAmount = 2;
          let assetAmountEth: BigNumber;
          let balanceCaller: BigNumber;
          let balanceReceiver: BigNumber;
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
            expect(await vault.balanceOf(caller.address)).to.eq(
              parseEther('0'),
            );
          });
          it('balance of vault shares of the receiver should be 4.6666666..', async () => {
            expect(
              parseFloat(formatEther(await vault.balanceOf(receiver.address))),
            ).to.be.closeTo(2 + 2 / 0.75, 0.00001);
          });
        });
      });
    }

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
      const { callVault } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      await callVault.setIsCall(isCall);
      totalAssets = parseFloat(formatEther(await callVault.totalAssets()));
      console.log('Setup vault.');

      maturity = minMaturity;
      spreadUnlockingRate = spread / (minMaturity - startTime);

      await callVault.afterBuy(
        minMaturity,
        parseEther(premium.toString()),
        maturity - startTime,
        parseEther(size.toString()),
        parseEther(spread.toString()),
        parseEther(strike.toString()),
      );
      afterBuyTimestamp = await now();
      console.log('Processed afterBuy.');
      return { vault: callVault };
    }

    it('lastSpreadUnlockUpdate should equal the time we executed afterBuy as we updated the state there', async () => {
      const { vault } = await setupAfterBuyVault(true);
      expect(await vault.lastSpreadUnlockUpdate()).to.eq(afterBuyTimestamp);
    });

    it('spreadUnlockingRates should equal', async () => {
      expect(
        parseFloat(formatEther(await callVault.spreadUnlockingRate())),
      ).to.be.closeTo(spreadUnlockingRate, 0.000000000000000001);
    });

    it('total assets should equal', async () => {
      expect(parseFloat(formatEther(await callVault.totalAssets()))).to.eq(
        totalAssets + premium + spread,
      );
    });

    it('positionSize should equal ', async () => {
      const positionSize = await callVault.positionSize(
        maturity,
        parseEther(strike.toString()),
      );
      expect(parseFloat(formatEther(positionSize))).to.eq(size);
    });

    it('spreadUnlockingRate / ticks', async () => {
      expect(
        parseFloat(formatEther(await callVault.spreadUnlockingTicks(maturity))),
      ).to.be.closeTo(spreadUnlockingRate, 0.000000000000000001);
    });

    it('totalLockedSpread should equa', async () => {
      expect(
        parseFloat(formatEther(await callVault.totalLockedSpread())),
      ).to.eq(spread);
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
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        const maturity = 1678435200 + ONE_WEEK;
        const size = parseEther('2');
        const strike1 = parseEther('1000');
        const strike2 = parseEther('2000');
        let totalLockedAssets: any;
        let newLockedAfterSettlement: any;
        let newTotalAssets: any;
        let vault: UnderwriterVaultMock;
        async function setup() {
          let { deployer, base, quote, oracleAdapter, p } = await loadFixture(
            vaultSetup,
          );
          let deposit: any;

          if (isCall) {
            deposit = 10;
            vault = callVault;
            totalLockedAssets = parseEther('5');
            newLockedAfterSettlement = parseEther('1');
            newTotalAssets = 9.333333333333;
          } else {
            deposit = 10000;
            vault = putVault;
            totalLockedAssets = parseEther('7120');
            newLockedAfterSettlement = parseEther('1120');
            newTotalAssets = 9000;
          }

          console.log('Depositing assets.');
          await addDeposit(vault, caller, deposit, base, quote);
          expect(await vault.totalAssets()).to.eq(
            parseEther(deposit.toString()),
          );
          console.log('Deposited assets.');

          const infos = [
            {
              maturity: maturity,
              strikes: [strike1, strike2],
              sizes: [size, size],
            },
          ];
          await vault.setListingsAndSizes(infos);
          await vault.increaseTotalLockedAssets(totalLockedAssets);

          for (const strike of [strike1, strike2]) {
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
          }
          await vault.connect(caller).mintFromPool(strike1, maturity, size);
          await vault.connect(caller).mintFromPool(strike2, maturity, size);
          await increaseTo(maturity);
          await vault.connect(caller).settleMaturity(maturity);
        }
        it('totalAssets should be reduced by the settlementValue and equal 9.986666666666', async () => {
          await loadFixture(setup);
          expect(
            parseFloat(formatEther(await vault.totalAssets())),
          ).to.be.closeTo(newTotalAssets, 0.000000000001);
        });
        it('the position size should be reduced by the amount of settled options', async () => {
          expect(await vault.totalLockedAssets()).to.eq(
            newLockedAfterSettlement,
          );
        });
      });
    }
  });

  describe('#settle', () => {
    const t0 = 1678435200;
    const t1 = t0 + ONE_WEEK;
    const t2 = t0 + 2 * ONE_WEEK;
    let strikedict = {};
    let vault: UnderwriterVaultMock;

    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        async function setupVaultForSettlement() {
          let { callVault, putVault, deployer, base, quote, oracleAdapter, p } =
            await loadFixture(vaultSetup);

          let totalAssets: any;
          let totalLockedAssets: any;

          if (isCall) {
            vault = callVault;
            totalAssets = 100;
            totalLockedAssets = parseEther('20');
          } else {
            totalAssets = 100000;
            vault = putVault;
            totalLockedAssets = parseEther('20000');
            quote.mint(caller.address, parseEther(totalAssets.toString()));
          }

          const striket00 = parseEther('1000');
          const striket01 = parseEther('2000');
          const striket10 = parseEther('1800');
          const striket20 = parseEther('1200');
          const striket21 = parseEther('1300');
          const striket22 = parseEther('2000');

          const strikest0 = [striket00, striket01];
          const strikest1 = [striket10];
          const strikest2 = [striket20, striket21, striket22];

          strikedict[t0] = strikest0;
          strikedict[t1] = strikest1;
          strikedict[t2] = strikest2;

          const infos = [
            {
              maturity: t0,
              strikes: strikest0,
              sizes: [2, 1].map((el) => parseEther(el.toString())),
            },
            {
              maturity: t1,
              strikes: strikest1,
              sizes: [1].map((el) => parseEther(el.toString())),
            },
            {
              maturity: t2,
              strikes: strikest2,
              sizes: [2, 3, 1].map((el) => parseEther(el.toString())),
            },
          ];

          console.log('Depositing assets.');
          await addDeposit(vault, caller, totalAssets, base, quote);
          expect(await vault.totalAssets()).to.eq(
            parseEther(totalAssets.toString()),
          );
          console.log('Deposited assets.');

          await vault.setListingsAndSizes(infos);
          await vault.increaseTotalLockedAssets(totalLockedAssets);
          for (let info of infos) {
            for (const [i, strike] of info.strikes.entries()) {
              await createPool(
                strike,
                info.maturity,
                isCall,
                deployer,
                base,
                quote,
                oracleAdapter,
                p,
              );
              console.log(
                `Minting ${info.sizes[i]} options with strike ${strike} and maturity ${info.maturity}.`,
              );
              await vault
                .connect(caller)
                .mintFromPool(strike, info.maturity, info.sizes[i]);
            }
          }
        }

        const tests = [
          { timestamp: t0 - ONE_HOUR, minMaturity: t0, maxMaturity: t2 },
          { timestamp: t0, minMaturity: t1, maxMaturity: t2 },
          { timestamp: t0 + ONE_HOUR, minMaturity: t1, maxMaturity: t2 },
          { timestamp: t1, minMaturity: t2, maxMaturity: t2 },
          { timestamp: t1 + ONE_HOUR, minMaturity: t2, maxMaturity: t2 },
          { timestamp: t2, minMaturity: 0, maxMaturity: 0 },
          { timestamp: t2 + ONE_HOUR, minMaturity: 0, maxMaturity: 0 },
        ];

        const callTests = [
          { newLocked: 20, newTotalAssets: 100 },
          { newLocked: 17, newTotalAssets: 99.333333 },
          { newLocked: 17, newTotalAssets: 99.333333 },
          { newLocked: 16, newTotalAssets: 99.333333 },
          { newLocked: 16, newTotalAssets: 99.333333 },
          { newLocked: 10, newTotalAssets: 98.533333 },
          { newLocked: 10, newTotalAssets: 98.533333 },
        ];

        const putTests = [
          { newLocked: 20000, newTotalAssets: 100000 },
          { newLocked: 16000, newTotalAssets: 99500 },
          { newLocked: 16000, newTotalAssets: 99500 },
          { newLocked: 14200, newTotalAssets: 99200 },
          { newLocked: 14200, newTotalAssets: 99200 },
          { newLocked: 5900, newTotalAssets: 98700 },
          { newLocked: 5900, newTotalAssets: 98700 },
        ];

        const amountsList = isCall ? callTests : putTests;
        let counter = 0;
        tests.forEach(async (test) => {
          let amounts = amountsList[counter];
          describe(`timestamp ${test.timestamp}`, () => {
            it(`totalAssets equals ${amounts.newTotalAssets}`, async () => {
              await loadFixture(setupVaultForSettlement);
              await increaseTo(test.timestamp);
              await vault.settle();

              let delta = isCall ? 0.00001 : 0;

              expect(
                parseFloat(formatEther(await vault.totalAssets())),
              ).to.be.closeTo(amounts.newTotalAssets, delta);
            });
            it(`totalLocked equals ${amounts.newLocked}`, async () => {
              let totalLocked = await vault.totalLockedAssets();
              let expected = parseEther(amounts.newLocked.toString());
              expect(totalLocked).to.eq(expected);
            });
            it(`minMaturity equals ${test.minMaturity}`, async () => {
              let minMaturity = await vault.minMaturity();
              expect(minMaturity).to.eq(test.minMaturity);
            });
            it(`maxMaturity equals ${test.maxMaturity}`, async () => {
              let maxMaturity = await vault.maxMaturity();
              expect(maxMaturity).to.eq(test.maxMaturity);
            });
            it(`expired position sizes equal zero`, async () => {
              if ([t0, t1, t2].includes(test.timestamp)) {
                let strikes = strikedict[test.timestamp];
                strikes.forEach(async (strike) => {
                  let size = await vault.positionSize(test.timestamp, strike);
                  expect(size).to.eq(parseEther('0'));
                });
              }
            });
            counter++;
          });
        });
      });
    }
  });

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
      const { callVault } = await loadFixture(vaultSetup);
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
      await callVault.setListingsAndSizes(infos);
      await callVault.setLastSpreadUnlockUpdate(startTime);
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

      await callVault.increaseSpreadUnlockingTick(t0, surt0);
      await callVault.increaseSpreadUnlockingTick(t1, surt1);
      await callVault.increaseSpreadUnlockingTick(t2, surt2);
      spreadUnlockingRate =
        spreadUnlockingRatet0 + spreadUnlockingRatet1 + spreadUnlockingRatet2;
      await callVault.increaseSpreadUnlockingRate(
        parseEther(spreadUnlockingRate.toFixed(18).toString()),
      );
      await callVault.increaseTotalLockedSpread(totalLockedFormatted);
    }

    describe('#getTotalLockedSpread', () => {
      it('At startTime + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        await loadFixture(setupSpreadsVault);
        await increaseTo(startTime + ONE_DAY);
        expect(
          parseFloat(formatEther(await callVault.getTotalLockedSpread())),
        ).to.be.closeTo(16.4668, 0.001);
      });

      it('At maturity t0 totalLockedSpread should approximately equal 7.268', async () => {
        // 7 / 14 * 11.2 + 3 / 10 * 5.56 = 7.268
        await increaseTo(t0);
        expect(
          parseFloat(formatEther(await callVault.getTotalLockedSpread())),
        ).to.be.closeTo(7.268, 0.001);
      });

      it('At t0 + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        // 6 / 14 * 11.2 + 2 / 10 * 5.56 = 5.912
        await increaseTo(t0 + ONE_DAY);
        expect(
          parseFloat(formatEther(await callVault.getTotalLockedSpread())),
        ).to.be.closeTo(5.912, 0.001);
      });

      it('At maturity t1 totalLockedSpread should approximately equal 3.2', async () => {
        // 11.2 * 3 / 14 = 3.2
        await increaseTo(t1);
        expect(
          parseFloat(formatEther(await callVault.getTotalLockedSpread())),
        ).to.be.closeTo(3.2, 0.001);
      });

      it('At t1 + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        // 3 / 14 * 11.2 = 2.4
        await increaseTo(t1 + ONE_DAY);
        expect(
          parseFloat(formatEther(await callVault.getTotalLockedSpread())),
        ).to.be.closeTo(2.4, 0.001);
      });

      it('At maturity t2 totalLockedSpread should approximately equal 0.0', async () => {
        // 0
        await increaseTo(t2);
        expect(
          parseFloat(formatEther(await callVault.getTotalLockedSpread())),
        ).to.be.closeTo(0.0, 0.0000001);
      });

      it('At maturity t2 + 7 days totalLockedSpread should approximately equal 0.0', async () => {
        // 0
        await increaseTo(t0 + 7 * ONE_DAY);
        expect(
          parseFloat(formatEther(await callVault.getTotalLockedSpread())),
        ).to.be.closeTo(0.0, 0.0000001);
      });
    });

    describe('#updateState', () => {
      it('At startTime + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        await loadFixture(setupSpreadsVault);
        await increaseTo(startTime + ONE_DAY);
        await callVault.updateState();
        expect(
          parseFloat(formatEther(await callVault.totalLockedSpread())),
        ).to.be.closeTo(16.4668, 0.001);
        expect(
          parseFloat(formatEther(await callVault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);
        expect(await callVault.lastSpreadUnlockUpdate()).to.eq(await now());
      });

      it('At maturity t0 totalLockedSpread should approximately equal 7.268', async () => {
        // 7 / 14 * 11.2 + 3 / 10 * 5.56 = 7.268
        await loadFixture(setupSpreadsVault);
        await increaseTo(t0);
        await callVault.updateState();
        expect(
          parseFloat(formatEther(await callVault.totalLockedSpread())),
        ).to.be.closeTo(7.268, 0.001);
        spreadUnlockingRate = spreadUnlockingRatet1 + spreadUnlockingRatet2;
        expect(
          parseFloat(formatEther(await callVault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);

        expect(await callVault.lastSpreadUnlockUpdate()).to.eq(await now());
      });

      it('At t0 + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        // 6 / 14 * 11.2 + 2 / 10 * 5.56 = 5.912
        await loadFixture(setupSpreadsVault);
        await increaseTo(t0 + ONE_DAY);
        await callVault.updateState();
        expect(
          parseFloat(formatEther(await callVault.totalLockedSpread())),
        ).to.be.closeTo(5.912, 0.001);
        spreadUnlockingRate = spreadUnlockingRatet1 + spreadUnlockingRatet2;
        expect(
          parseFloat(formatEther(await callVault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);
        expect(await callVault.lastSpreadUnlockUpdate()).to.eq(await now());
      });

      it('At maturity t1 totalLockedSpread should approximately equal 3.2', async () => {
        // 11.2 * 3 / 14 = 3.2
        await loadFixture(setupSpreadsVault);
        await increaseTo(t1);
        await callVault.updateState();
        expect(
          parseFloat(formatEther(await callVault.totalLockedSpread())),
        ).to.be.closeTo(3.2, 0.001);
        expect(
          parseFloat(formatEther(await callVault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRatet2, 0.001);
        expect(await callVault.lastSpreadUnlockUpdate()).to.eq(await now());
      });

      it('At t1 + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        // 3 / 14 * 11.2 = 2.4
        await loadFixture(setupSpreadsVault);
        await increaseTo(t1 + ONE_DAY);
        await callVault.updateState();
        expect(
          parseFloat(formatEther(await callVault.totalLockedSpread())),
        ).to.be.closeTo(2.4, 0.001);
        expect(
          parseFloat(formatEther(await callVault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRatet2, 0.001);
        expect(await callVault.lastSpreadUnlockUpdate()).to.eq(await now());
      });

      it('At maturity t2 totalLockedSpread should approximately equal 0.0', async () => {
        await loadFixture(setupSpreadsVault);
        await increaseTo(t2);
        await callVault.updateState();
        expect(
          parseFloat(formatEther(await callVault.totalLockedSpread())),
        ).to.be.closeTo(0.0, 0.001);
        expect(
          parseFloat(formatEther(await callVault.spreadUnlockingRate())),
        ).to.be.closeTo(0.0, 0.001);
        expect(await callVault.lastSpreadUnlockUpdate()).to.eq(await now());
      });

      it('Run through all of the above', async () => {
        await loadFixture(setupSpreadsVault);
        await increaseTo(startTime + ONE_DAY);
        await callVault.updateState();
        expect(
          parseFloat(formatEther(await callVault.totalLockedSpread())),
        ).to.be.closeTo(16.4668, 0.001);
        expect(
          parseFloat(formatEther(await callVault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);
        expect(await callVault.lastSpreadUnlockUpdate()).to.eq(await now());
        await increaseTo(t0);
        await callVault.updateState();
        expect(
          parseFloat(formatEther(await callVault.totalLockedSpread())),
        ).to.be.closeTo(7.268, 0.001);
        spreadUnlockingRate = spreadUnlockingRatet1 + spreadUnlockingRatet2;
        expect(
          parseFloat(formatEther(await callVault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);

        expect(await callVault.lastSpreadUnlockUpdate()).to.eq(await now());
        await increaseTo(t0 + ONE_DAY);
        await callVault.updateState();
        expect(
          parseFloat(formatEther(await callVault.totalLockedSpread())),
        ).to.be.closeTo(5.912, 0.001);
        spreadUnlockingRate = spreadUnlockingRatet1 + spreadUnlockingRatet2;
        expect(
          parseFloat(formatEther(await callVault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);
        expect(await callVault.lastSpreadUnlockUpdate()).to.eq(await now());
        await increaseTo(t1);
        await callVault.updateState();
        expect(
          parseFloat(formatEther(await callVault.totalLockedSpread())),
        ).to.be.closeTo(3.2, 0.001);
        expect(
          parseFloat(formatEther(await callVault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRatet2, 0.001);
        expect(await callVault.lastSpreadUnlockUpdate()).to.eq(await now());
        await increaseTo(t1 + ONE_DAY);
        await callVault.updateState();
        expect(
          parseFloat(formatEther(await callVault.totalLockedSpread())),
        ).to.be.closeTo(2.4, 0.001);
        expect(
          parseFloat(formatEther(await callVault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRatet2, 0.001);
        expect(await callVault.lastSpreadUnlockUpdate()).to.eq(await now());
        await increaseTo(t2);
        await callVault.updateState();
        expect(
          parseFloat(formatEther(await callVault.totalLockedSpread())),
        ).to.be.closeTo(0.0, 0.001);
        expect(
          parseFloat(formatEther(await callVault.spreadUnlockingRate())),
        ).to.be.closeTo(0.0, 0.001);
        expect(await callVault.lastSpreadUnlockUpdate()).to.eq(await now());
      });
    });
  });

  describe('#asset', () => {
    it('returns base asset for callVault', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      const asset = await callVault.asset();
      expect(asset).to.eq(base.address);
    });
    it('returns quote asset for putVault', async () => {
      const { putVault } = await loadFixture(vaultSetup);
      const asset = await putVault.asset();
      expect(asset).to.eq(quote.address);
    });
  });

  describe('#_removeListing', () => {
    beforeEach(async () => {});
    it('returns base asset for callVault', async () => {});
  });
});
