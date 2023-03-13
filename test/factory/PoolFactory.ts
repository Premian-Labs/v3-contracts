import { expect } from 'chai';
import { ethers } from 'hardhat';
import { ERC20Mock__factory, IPool__factory } from '../../typechain';
import { parseEther, parseUnits } from 'ethers/lib/utils';
import { PoolUtil } from '../../utils/PoolUtil';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import {
  getLastFridayOfMonth,
  getValidMaturity,
  latest,
  ONE_DAY,
  ONE_WEEK,
} from '../../utils/time';

import { tokens } from '../../utils/addresses';
import { BigNumber } from 'ethers';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

describe('PoolFactory', () => {
  const isCall = true;
  const strike = parseEther('1000'); // ATM

  async function deploy() {
    const [deployer] = await ethers.getSigners();

    const base = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
    const quote = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

    const oracleAdapter = await deployMockContract(deployer as any, [
      'function quote(address,address) external view returns (uint256)',
      'function quoteFrom(address,address,uint256) external view returns (uint256)',
      'function upsertPair(address,address) external',
    ]);

    await oracleAdapter.mock.quote.returns(parseUnits('1000', 18));
    await oracleAdapter.mock.quoteFrom.returns(parseUnits('1000', 18));
    await oracleAdapter.mock.upsertPair.returns();

    const p = await PoolUtil.deploy(
      deployer,
      tokens.WETH.address,
      oracleAdapter.address,
      deployer.address,
      parseEther('0.1'), // 10%
      true,
      true,
    );

    const maturity = await getValidMaturity(10, 'months');
    const blockTimestamp = await latest();

    const poolKey = {
      base: base.address,
      quote: quote.address,
      oracleAdapter: oracleAdapter.address,
      strike,
      maturity: BigNumber.from(maturity),
      isCallPool: isCall,
    } as const;

    Object.freeze(poolKey);

    return {
      deployer,
      p,
      base,
      quote,
      oracleAdapter,
      maturity,
      blockTimestamp,
      poolKey,
    };
  }

  describe('#getPoolAddress', () => {
    it('should return address(0) if no pool has been deployed with given parameters', async () => {
      const { poolKey, p } = await loadFixture(deploy);

      expect(await p.poolFactory.getPoolAddress(poolKey)).to.eq(
        ethers.constants.AddressZero,
      );
    });

    it('should return the pool address if a pool with given parameters has been deployed', async () => {
      const { poolKey, p } = await loadFixture(deploy);

      const tx = await p.poolFactory.deployPool(poolKey, {
        value: parseEther('1'),
      });

      const r = await tx.wait(1);
      const poolAddress = (r as any).events[0].args.poolAddress;

      expect(await p.poolFactory.getPoolAddress(poolKey)).to.eq(poolAddress);
    });
  });

  describe('#deployPool', () => {
    it('should properly deploy the pool', async () => {
      const { poolKey, p, deployer, base, quote, oracleAdapter, maturity } =
        await loadFixture(deploy);

      const tx = await p.poolFactory.deployPool(poolKey, {
        value: parseEther('1'),
      });

      const r = await tx.wait(1);
      const poolAddress = (r as any).events[0].args.poolAddress;

      const pool = IPool__factory.connect(poolAddress, deployer);
      const poolSettings = await pool.getPoolSettings();

      expect([
        poolSettings.base,
        poolSettings.quote,
        poolSettings.oracleAdapter,
        poolSettings.strike,
        poolSettings.maturity,
        poolSettings.isCallPool,
      ]).to.deep.eq([
        base.address,
        quote.address,
        oracleAdapter.address,
        strike,
        maturity,
        isCall,
      ]);
    });

    it('should revert if base and base are identical', async () => {
      const { poolKey, p, quote } = await loadFixture(deploy);

      await expect(
        p.poolFactory.deployPool(
          { ...poolKey, base: quote.address },
          {
            value: parseEther('1'),
          },
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__IdenticalAddresses',
      );
    });

    it('should revert if base, base, or oracleAdapter are zero address', async () => {
      const { poolKey, p } = await loadFixture(deploy);

      await expect(
        p.poolFactory.deployPool(
          {
            ...poolKey,
            quote: ethers.constants.AddressZero,
          },
          {
            value: parseEther('1'),
          },
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__ZeroAddress',
      );

      await expect(
        p.poolFactory.deployPool(
          {
            ...poolKey,
            base: ethers.constants.AddressZero,
          },
          {
            value: parseEther('1'),
          },
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__ZeroAddress',
      );

      await expect(
        p.poolFactory.deployPool(
          {
            ...poolKey,
            oracleAdapter: ethers.constants.AddressZero,
          },
          {
            value: parseEther('1'),
          },
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__ZeroAddress',
      );
    });

    it('should revert if pool has already been deployed', async () => {
      const { poolKey, p } = await loadFixture(deploy);

      await p.poolFactory.deployPool(poolKey, {
        value: parseEther('1'),
      });

      await expect(
        p.poolFactory.deployPool(poolKey, {
          value: parseEther('1'),
        }),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__PoolAlreadyDeployed',
      );
    });

    it('should revert if strike is zero', async () => {
      const { poolKey, p } = await loadFixture(deploy);

      await expect(
        p.poolFactory.deployPool(
          { ...poolKey, strike: 0 },
          {
            value: parseEther('1'),
          },
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__OptionStrikeEqualsZero',
      );
    });

    it('should revert if strike price is not within strike interval', async () => {
      const { poolKey, p } = await loadFixture(deploy);

      // strike interval: 100
      for (let strike of [
        parseEther('99990'),
        parseEther('1050'),
        parseEther('950'),
        parseEther('11'),
      ]) {
        await expect(
          p.poolFactory.deployPool(
            { ...poolKey, strike },
            {
              value: parseEther('1'),
            },
          ),
        ).to.be.revertedWithCustomError(
          p.poolFactory,
          'PoolFactory__OptionStrikeInvalid',
        );
      }
    });

    it('should revert if daily option maturity has expired', async () => {
      const { poolKey, p, blockTimestamp } = await loadFixture(deploy);

      await expect(
        p.poolFactory.deployPool(
          { ...poolKey, maturity: blockTimestamp },
          {
            value: parseEther('1'),
          },
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__OptionExpired',
      );
    });

    it('should revert if daily option maturity is not at 8AM UTC', async () => {
      const { poolKey, p } = await loadFixture(deploy);

      await expect(
        p.poolFactory.deployPool(
          {
            ...poolKey,
            maturity: (await getValidMaturity(2, 'days')) + 1,
          },
          {
            value: parseEther('1'),
          },
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__OptionMaturityNot8UTC',
      );
    });

    it('should revert if weekly option maturity not on Friday', async () => {
      const { poolKey, p } = await loadFixture(deploy);

      await expect(
        p.poolFactory.deployPool(
          {
            ...poolKey,
            maturity: (await getValidMaturity(2, 'weeks')) - ONE_DAY,
          },
          {
            value: parseEther('1'),
          },
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__OptionMaturityNotFriday',
      );
    });

    it('should revert if monthly option maturity not on last Friday', async () => {
      const { poolKey, p } = await loadFixture(deploy);

      await expect(
        p.poolFactory.deployPool(
          {
            ...poolKey,
            maturity: (await getValidMaturity(2, 'months')) - ONE_WEEK,
          },
          {
            value: parseEther('1'),
          },
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__OptionMaturityNotLastFriday',
      );
    });

    it('should revert if monthly option maturity exceeds 365 days', async () => {
      const { poolKey, p } = await loadFixture(deploy);

      await expect(
        p.poolFactory.deployPool(
          {
            ...poolKey,
            maturity: await getLastFridayOfMonth(await latest(), 13),
          },
          {
            value: parseEther('1'),
          },
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__OptionMaturityExceedsMax',
      );
    });
  });
});
