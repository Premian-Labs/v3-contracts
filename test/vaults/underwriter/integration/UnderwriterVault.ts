import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import { vaultSetup, deposit, trade, withdraw, mint, redeem } from './Helpers';
import {
  formatEther,
  formatUnits,
  parseEther,
  parseUnits,
} from 'ethers/lib/utils';
import { expect } from 'chai';
import {
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
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { PoolUtil } from '../../../../utils/PoolUtil';
import { PoolKey, TokenType } from '../../../../utils/sdk/types';
import exp from 'constants';
import { now } from 'moment-timezone';

let vault: UnderwriterVaultMock;

describe('UnderwriterVault integration tests', () => {
  it('should be able to deposit and then withdraw from the vault', async () => {
    let { lp, trader, base, quote, optionMath, callVault, putVault, maturity } =
      await loadFixture(vaultSetup);

    const token = base;

    // Make a deposit
    await deposit(callVault, lp, base, quote, 15);
    await mint(callVault, lp, base, quote, 10);

    let pps = parseFloat(formatEther(await callVault.getPricePerShare()));

    // Make a trade
    await trade(callVault, trader, base, quote, 1500, maturity, 3);

    // await increaseTo(maturity + 3 * ONE_DAY);
    //
    // let available = parseFloat(
    //   formatEther(await callVault.maxWithdraw(lp.address)),
    // );
    // console.log(available);

    // Withdraw at 1 day after maturity
    await withdraw(callVault, lp, base, quote, 12);

    await redeem(callVault, lp, base, quote, 10);

    // let balance = parseFloat(formatEther(await token.balanceOf(lp.address)));
    // console.log(balance);
  });
});
