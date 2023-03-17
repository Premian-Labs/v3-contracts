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
        isCall: true,
        isBuy: true,
        error: null,
        message: 'trying to buy a call option from the call vault',
      },
      {
        isCallVault: true,
        isCall: true,
        isBuy: false,
        error: 'Vault__TradeMustBeBuy',
        message: 'trying to sell a call option to the call vault',
      },
      {
        isCallVault: true,
        isCall: false,
        isBuy: true,
        error: 'Vault__OptionTypeMismatchWithVault',
        message: 'trying to buy a put option from the call vault',
      },
      {
        isCallVault: true,
        isCall: false,
        isBuy: false,
        error: 'Vault__TradeMustBeBuy',
        message: 'trying to sell a put option to the call vault',
      },
      {
        isCallVault: false,
        isCall: true,
        isBuy: true,
        error: 'Vault__OptionTypeMismatchWithVault',
        message: 'trying to buy a call option from the put vault',
      },
      {
        isCallVault: false,
        isCall: true,
        isBuy: false,
        error: 'Vault__TradeMustBeBuy',
        message: 'trying to sell a call option to the put vault',
      },
      {
        isCallVault: false,
        isCall: false,
        isBuy: true,
        error: null,
        message: 'trying to buy a put option from the put vault',
      },
      {
        isCallVault: false,
        isCall: false,
        isBuy: false,
        error: 'Vault__TradeMustBeBuy',
        message: 'trying to sell a put option to the put vault',
      },
    ];

    tests.forEach(async (test) => {
      if (test.error != null) {
        it(`should raise ${test.error} error when ${test.message}`, async () => {
          const { callVault, putVault } = await loadFixture(vaultSetup);
          const vault = test.isCallVault ? callVault : putVault;

          await expect(
            vault.ensureTradeableWithVault(test.isCall, test.isBuy),
          ).to.be.revertedWithCustomError(callVault, test.error);
        });
      } else {
        it(`should not raise an error when ${test.message}`, async () => {
          const { callVault, putVault } = await loadFixture(vaultSetup);
          const vault = test.isCallVault ? callVault : putVault;

          await expect(vault.ensureTradeableWithVault(test.isCall, test.isBuy));
          expect(true);
        });
      }
    });
  });
});
