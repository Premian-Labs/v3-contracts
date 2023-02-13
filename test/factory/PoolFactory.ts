import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { ERC20Mock, ERC20Mock__factory, IPool__factory } from '../../typechain';
import { parseEther, parseUnits } from 'ethers/lib/utils';
import { PoolUtil } from '../../utils/PoolUtil';
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract';
import {
  getLastFridayOfMonth,
  getValidMaturity,
  now,
  ONE_DAY,
  ONE_WEEK,
  revertToSnapshotAfterEach,
} from '../../utils/time';

import moment from 'moment-timezone';
import { beforeEach } from 'mocha';
import { PoolKey } from '../../utils/sdk/types';
import { BigNumber } from 'ethers';

moment.tz.setDefault('UTC');

describe('PoolFactory', () => {
  let deployer: SignerWithAddress;

  let p: PoolUtil;

  let base: ERC20Mock;
  let quote: ERC20Mock;
  let baseOracle: MockContract;
  let quoteOracle: MockContract;

  let isCall = true;
  let strike = parseEther('1000'); // ATM
  let maturity: number;
  let blockTimestamp: number;
  let poolKey: PoolKey;

  before(async () => {
    [deployer] = await ethers.getSigners();

    base = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
    quote = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

    baseOracle = await deployMockContract(deployer as any, [
      'function latestAnswer() external view returns (int256)',
      'function decimals () external view returns (uint8)',
    ]);

    await baseOracle.mock.latestAnswer.returns(parseUnits('1000', 8));
    await baseOracle.mock.decimals.returns(8);

    quoteOracle = await deployMockContract(deployer as any, [
      'function latestAnswer() external view returns (int256)',
      'function decimals () external view returns (uint8)',
    ]);

    await quoteOracle.mock.latestAnswer.returns(parseUnits('1', 8));
    await quoteOracle.mock.decimals.returns(8);

    p = await PoolUtil.deploy(
      deployer,
      base.address,
      baseOracle.address,
      deployer.address,
      parseEther('0.1'), // 10%
      true,
      true,
    );

    maturity = await getValidMaturity(10, 'months');
    blockTimestamp = await now();
  });

  beforeEach(async () => {
    poolKey = {
      base: base.address,
      quote: quote.address,
      baseOracle: baseOracle.address,
      quoteOracle: quoteOracle.address,
      strike,
      maturity: BigNumber.from(maturity),
      isCallPool: isCall,
    };
  });

  revertToSnapshotAfterEach(async () => {});

  describe('#isPoolDeployed', () => {
    it('should return false if no pool has been deployed with given parameters', async () => {
      expect(await p.poolFactory.isPoolDeployed(poolKey)).to.be.false;
    });

    it('should return true if a pool with given parameters has been deployed', async () => {
      await p.poolFactory.deployPool(poolKey, { value: parseEther('1') });

      expect(await p.poolFactory.isPoolDeployed(poolKey)).to.be.true;
    });
  });

  describe('#deployPool', () => {
    it('should properly deploy the pool', async () => {
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
        poolSettings.baseOracle,
        poolSettings.quoteOracle,
        poolSettings.strike,
        poolSettings.maturity,
        poolSettings.isCallPool,
      ]).to.deep.eq([
        base.address,
        quote.address,

        baseOracle.address,
        quoteOracle.address,
        strike,
        maturity,
        isCall,
      ]);
    });

    it('should revert if base and base are identical', async () => {
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

    it('should revert if quoteOracle and baseOracle are identical', async () => {
      await expect(
        p.poolFactory.deployPool(
          {
            ...poolKey,
            baseOracle: quoteOracle.address,
          },
          {
            value: parseEther('1'),
          },
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__IdenticalAddresses',
      );
    });

    it('should revert if base, base, quoteOracle, or baseOracle are zero address', async () => {
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
            quoteOracle: ethers.constants.AddressZero,
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
            baseOracle: ethers.constants.AddressZero,
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
      await expect(
        p.poolFactory.deployPool(
          {
            ...poolKey,
            maturity: await getLastFridayOfMonth(await now(), 13),
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
