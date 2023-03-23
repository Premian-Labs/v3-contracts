import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import { addMockDeposit, vaultSetup } from '../VaultSetup';
import {
  formatEther,
  formatUnits,
  parseEther,
  parseUnits,
} from 'ethers/lib/utils';
import { expect } from 'chai';
import {
  getValidMaturity,
  increaseTo,
  latest,
  ONE_DAY,
  ONE_HOUR,
  ONE_WEEK,
} from '../../../../utils/time';
import {
  ERC20Mock,
  IPoolMock,
  UnderwriterVaultMock,
} from '../../../../typechain';
import { BigNumber } from 'ethers';
import { setMaturities } from '../VaultSetup';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { MockContract } from '@ethereum-waffle/mock-contract';
import { PoolUtil } from '../../../../utils/PoolUtil';
import { PoolKey, TokenType } from '../../../../utils/sdk/types';
import exp from 'constants';
import { start } from 'repl';

let startTime: number;
let vault: UnderwriterVaultMock;

describe('UnderwriterVault.fees', () => {
  describe('#_chargeManagementFees', () => {
    startTime = 10000000;
    const tests = [
      {
        totalAssets: 11.2,
        lastFeeEventTimestamp: startTime - ONE_DAY,
        timestamp: startTime + ONE_DAY,
        feesCollected: 1,
        managementFeeRate: 0.01,
        feesCollectedAfter: 1 + (11.2 * 0.01 * 2) / 365,
      },
      {
        totalAssets: 1.2,
        lastFeeEventTimestamp: startTime - ONE_DAY,
        timestamp: startTime + ONE_DAY,
        feesCollected: 0.0123,
        managementFeeRate: 0.0,
        feesCollectedAfter: 0.0123,
      },
      {
        totalAssets: 501.3,
        lastFeeEventTimestamp: startTime - ONE_DAY,
        timestamp: startTime + 6 * ONE_HOUR,
        feesCollected: 0.0123,
        managementFeeRate: 0.05,
        feesCollectedAfter: 0.0123 + (501.3 * 0.05 * (1 + 1 / 4)) / 365,
      },
    ];

    tests.forEach(async (test) => {
      async function setup() {
        let { callVault } = await loadFixture(vaultSetup);
        vault = callVault;
        await vault.setFeesCollected(parseEther(test.feesCollected.toString()));
        await vault.setLastFeeEventTimestamp(test.lastFeeEventTimestamp);
        await vault.setManagementFeeRate(
          parseEther(test.managementFeeRate.toString()),
        );
        await vault.chargeManagementFees(
          test.timestamp,
          parseEther(test.totalAssets.toString()),
        );
      }
      it(`fees collected after charging equals ${test.feesCollectedAfter}`, async () => {
        await loadFixture(setup);
        const feesCollected = parseFloat(
          formatEther(await vault.getFeesCollected()),
        );
        const delta = 1e-16;
        expect(feesCollected).to.be.closeTo(test.feesCollectedAfter, delta);
      });
      it(`lastFeeEventTimestamp equals ${test.timestamp}`, async () => {
        expect(await vault.getLastFeeEventTimestamp()).to.eq(test.timestamp);
      });
    });
  });
});
