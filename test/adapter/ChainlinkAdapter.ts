import {
  ChainlinkAdapter,
  ChainlinkAdapter__factory,
  ChainlinkOraclePriceStub__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import { feeds, tokens } from '../../utils/addresses';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { bnToAddress } from '@solidstate/library';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';

describe('ChainlinkAdapter', () => {
  async function deploy() {
    const [deployer] = await ethers.getSigners();

    const implementation = await new ChainlinkAdapter__factory(deployer).deploy(
      tokens.WETH.address,
      tokens.WBTC.address,
    );

    await implementation.deployed();

    const proxy = await new ProxyUpgradeableOwnable__factory(deployer).deploy(
      implementation.address,
    );

    await proxy.deployed();

    const instance = ChainlinkAdapter__factory.connect(proxy.address, deployer);

    await instance.batchRegisterFeedMappings(feeds);

    return { deployer, instance };
  }

  describe('#upsertPair', () => {
    it('should only emit UpdatedPathForPair when path is updated', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(
        instance.upsertPair(tokens.WETH.address, tokens.DAI.address),
      ).to.emit(instance, 'UpdatedPathForPair');

      let [isCached, _] = await instance.isPairSupported(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(isCached).to.be.true;

      await expect(
        instance.upsertPair(tokens.WETH.address, tokens.DAI.address),
      ).to.not.emit(instance, 'UpdatedPathForPair');

      [isCached, _] = await instance.isPairSupported(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(isCached).to.be.true;

      await instance.batchRegisterFeedMappings([
        {
          token: tokens.DAI.address,
          denomination: tokens.CHAINLINK_ETH.address,
          feed: bnToAddress(BigNumber.from(0)),
        },
      ]);

      await expect(
        instance.upsertPair(tokens.WETH.address, tokens.DAI.address),
      ).to.emit(instance, 'UpdatedPathForPair');

      [isCached, _] = await instance.isPairSupported(
        tokens.WETH.address,
        tokens.DAI.address,
      );
    });
  });
});
