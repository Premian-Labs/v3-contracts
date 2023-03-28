import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import {
  addMockDeposit,
  createPool,
  increaseTotalAssets,
  vaultSetup,
} from '../VaultSetup';
import { formatEther, parseEther, parseUnits } from 'ethers/lib/utils';
import { expect } from 'chai';
import {
  getValidMaturity,
  increaseTo,
  latest,
  ONE_DAY,
  ONE_HOUR,
  ONE_WEEK,
} from '../../../../utils/time';
import { ERC20Mock, UnderwriterVaultMock } from '../../../../typechain';
import { BigNumber } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

let startTime: number;
let spot: number;
let minMaturity: number;
let maxMaturity: number;

let t0: number;
let t1: number;
let t2: number;
let t3: number;

let vault: UnderwriterVaultMock;

let caller: SignerWithAddress;
let base: ERC20Mock;
let quote: ERC20Mock;

describe('test ensure functions', () => {
  describe('#_ensureTradeableWithVault', () => {
    let tests = [
      {
        isCallVault: true,
        isCallOption: true,
        isBuy: true,
        error: null,
        message: 'trying to buy a call option from the call vault',
      },
      {
        isCallVault: true,
        isCallOption: true,
        isBuy: false,
        error: 'Vault__TradeMustBeBuy',
        message: 'trying to sell a call option to the call vault',
      },
      {
        isCallVault: true,
        isCallOption: false,
        isBuy: true,
        error: 'Vault__OptionTypeMismatchWithVault',
        message: 'trying to buy a put option from the call vault',
      },
      {
        isCallVault: true,
        isCallOption: false,
        isBuy: false,
        error: 'Vault__TradeMustBeBuy',
        message: 'trying to sell a put option to the call vault',
      },
      {
        isCallVault: false,
        isCallOption: true,
        isBuy: true,
        error: 'Vault__OptionTypeMismatchWithVault',
        message: 'trying to buy a call option from the put vault',
      },
      {
        isCallVault: false,
        isCallOption: true,
        isBuy: false,
        error: 'Vault__TradeMustBeBuy',
        message: 'trying to sell a call option to the put vault',
      },
      {
        isCallVault: false,
        isCallOption: false,
        isBuy: true,
        error: null,
        message: 'trying to buy a put option from the put vault',
      },
      {
        isCallVault: false,
        isCallOption: false,
        isBuy: false,
        error: 'Vault__TradeMustBeBuy',
        message: 'trying to sell a put option to the put vault',
      },
    ];

    tests.forEach(async (test) => {
      if (test.error != null) {
        it(`should raise ${test.error} error when ${test.message}`, async () => {
          const { callVault } = await loadFixture(vaultSetup);
          vault = callVault;

          await expect(
            vault.ensureTradeableWithVault(
              test.isCallVault,
              test.isCallOption,
              test.isBuy,
            ),
          ).to.be.revertedWithCustomError(vault, test.error);
        });
      } else {
        it(`should not raise an error when ${test.message}`, async () => {
          const { callVault } = await loadFixture(vaultSetup);
          vault = callVault;

          await expect(
            vault.ensureTradeableWithVault(
              test.isCallVault,
              test.isCallOption,
              test.isBuy,
            ),
          ).to.not.be.rejected;
        });
      }
    });
  });

  describe('#_ensureValidOption', () => {
    let tests = [
      {
        timestamp: 1000,
        strike: parseEther('1500'),
        maturity: 800,
        error: 'Vault__OptionExpired',
        message: 'trading an expired option',
      },
      {
        timestamp: 1000,
        strike: parseEther('0'),
        maturity: 800,
        error: 'Vault__StrikeZero',
        message: 'trading an option with a strike equal to zero',
      },
      {
        timestamp: 1000,
        strike: parseEther('1500'),
        maturity: 1200,
        error: null,
        message: 'trading a valid option',
      },
      {
        timestamp: 1000,
        strike: parseEther('0'),
        maturity: 1200,
        error: 'Vault__StrikeZero',
        message: 'trading an option with a strike equal to zero',
      },
    ];

    tests.forEach(async (test) => {
      if (test.error != null) {
        it(`should raise ${test.error} error when ${test.message}`, async () => {
          const { callVault } = await loadFixture(vaultSetup);
          vault = callVault;

          await expect(
            vault.ensureValidOption(test.timestamp, test.strike, test.maturity),
          ).to.be.revertedWithCustomError(vault, test.error);
        });
      } else {
        it(`should not raise an error when ${test.message}`, async () => {
          const { callVault } = await loadFixture(vaultSetup);
          vault = callVault;

          await expect(
            vault.ensureValidOption(test.timestamp, test.strike, test.maturity),
          ).to.not.be.rejected;
        });
      }
    });
  });

  describe('#_ensureSufficientFunds', () => {
    let tests = [
      {
        isCallVault: true,
        size: parseEther('5'),
        strike: parseEther('1500'),
        availableAssets: parseEther('10'),
        error: null,
        message:
          'trying to buy 5 call contracts when there is 10 units of collateral available',
      },
      {
        isCallVault: true,
        size: parseEther('10'),
        strike: parseEther('1500'),
        availableAssets: parseEther('10'),
        error: 'Vault__InsufficientFunds',
        message:
          'trying to buy 10 call contracts when there is 10 units of collateral available',
      },
      {
        isCallVault: true,
        size: parseEther('12'),
        strike: parseEther('1500'),
        availableAssets: parseEther('10'),
        error: 'Vault__InsufficientFunds',
        message:
          'trying to buy 12 call contracts when there is 10 units of collateral available',
      },
      {
        isCallVault: false,
        size: parseEther('5'),
        strike: parseEther('1500'),
        availableAssets: parseEther('10000'),
        error: null,
        message:
          'trying to buy 5 put contracts when there is 5 units of collateral available',
      },
      {
        isCallVault: false,
        size: parseEther('5'),
        strike: parseEther('1500'),
        availableAssets: parseEther('7500'),
        error: 'Vault__InsufficientFunds',
        message:
          'trying to buy 5 put contracts when there is 5 units of collateral available',
      },
      {
        isCallVault: false,
        size: parseEther('5'),
        strike: parseEther('1500'),
        availableAssets: parseEther('5000'),
        error: 'Vault__InsufficientFunds',
        message:
          'trying to buy 5 put contracts when there is 5 units of collateral available',
      },
    ];

    tests.forEach(async (test) => {
      if (test.error != null) {
        it(`should raise ${test.error} error when ${test.message}`, async () => {
          const { callVault } = await loadFixture(vaultSetup);
          vault = callVault;

          await expect(
            vault.ensureSufficientFunds(
              test.isCallVault,
              test.strike,
              test.size,
              test.availableAssets,
            ),
          ).to.be.revertedWithCustomError(vault, test.error);
        });
      } else {
        it(`should not raise an error when ${test.message}`, async () => {
          const { callVault } = await loadFixture(vaultSetup);
          vault = callVault;

          await expect(
            vault.ensureSufficientFunds(
              test.isCallVault,
              test.strike,
              test.size,
              test.availableAssets,
            ),
          ).to.not.be.rejected;
        });
      }
    });
  });

  describe('#_ensureWithinTradeBounds', () => {
    let tests = [
      {
        value: parseEther('3'),
        minimum: parseEther('5'),
        maximum: parseEther('10'),
        signature: 'ensureWithinTradeBounds(string,uint256,uint256,uint256)',
        error: 'Vault__OutOfTradeBounds',
        message: 'below the lower bound',
      },
      {
        value: parseEther('5'),
        minimum: parseEther('5'),
        maximum: parseEther('10'),
        signature: 'ensureWithinTradeBounds(string,uint256,uint256,uint256)',
        error: null,
        message: 'equal to the lower bound',
      },
      {
        value: parseEther('7'),
        minimum: parseEther('5'),
        maximum: parseEther('10'),
        signature: 'ensureWithinTradeBounds(string,uint256,uint256,uint256)',
        error: null,
        message: 'within the bounds',
      },
      {
        value: parseEther('10'),
        minimum: parseEther('5'),
        maximum: parseEther('10'),
        signature: 'ensureWithinTradeBounds(string,uint256,uint256,uint256)',
        error: null,
        message: 'equal to the upper bound',
      },
      {
        value: parseEther('12'),
        minimum: parseEther('5'),
        maximum: parseEther('10'),
        signature: 'ensureWithinTradeBounds(string,uint256,uint256,uint256)',
        error: 'Vault__OutOfTradeBounds',
        message: 'above the upper bound',
      },
      {
        value: parseEther('-7'),
        minimum: parseEther('-5'),
        maximum: parseEther('5'),
        signature: 'ensureWithinTradeBounds(string,int256,int256,int256)',
        error: 'Vault__OutOfTradeBounds',
        message: 'below the lower bound',
      },
      {
        value: parseEther('-5'),
        minimum: parseEther('-5'),
        maximum: parseEther('5'),
        signature: 'ensureWithinTradeBounds(string,int256,int256,int256)',
        error: null,
        message: 'equal to the lower bound',
      },
      {
        value: parseEther('0'),
        minimum: parseEther('-5'),
        maximum: parseEther('5'),
        signature: 'ensureWithinTradeBounds(string,int256,int256,int256)',
        error: null,
        message: 'within the bounds',
      },
      {
        value: parseEther('5'),
        minimum: parseEther('-5'),
        maximum: parseEther('5'),
        signature: 'ensureWithinTradeBounds(string,int256,int256,int256)',
        error: null,
        message: 'equal to the upper bound',
      },
      {
        value: parseEther('7'),
        minimum: parseEther('-5'),
        maximum: parseEther('5'),
        signature: 'ensureWithinTradeBounds(string,int256,int256,int256)',
        error: 'Vault__OutOfTradeBounds',
        message: 'above the upper bound',
      },
    ];

    tests.forEach(async (test) => {
      if (test.error != null) {
        it(`should raise ${test.error} error when ${test.message}`, async () => {
          const { callVault } = await loadFixture(vaultSetup);
          vault = callVault;

          await expect(
            vault[test.signature](
              'value',
              test.value,
              test.minimum,
              test.maximum,
            ),
          ).to.be.revertedWithCustomError(vault, test.error);
        });
      } else {
        it(`should not raise an error when ${test.message}`, async () => {
          const { callVault } = await loadFixture(vaultSetup);
          vault = callVault;

          await expect(
            vault[test.signature](
              'value',
              test.value,
              test.minimum,
              test.maximum,
            ),
          ).to.not.be.rejected;
        });
      }
    });
  });
});
