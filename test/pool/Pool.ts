import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  PoolMock,
  PoolMock__factory,
  Premia,
  Premia__factory,
} from '../../typechain';
import { diamondCut } from '../../scripts/utils/diamond';
import { parseEther, parseUnits } from 'ethers/lib/utils';
import { BigNumber } from 'ethers';

describe('Pool', () => {
  let admin: SignerWithAddress;
  let poolDiamond: Premia;
  let pool: PoolMock;

  let snapshotId: number;

  before(async () => {
    [admin] = await ethers.getSigners();

    poolDiamond = await new Premia__factory(admin).deploy();

    const poolFactory = new PoolMock__factory(admin);
    const poolImpl = await poolFactory.deploy();

    let registeredSelectors = [
      poolDiamond.interface.getSighash('supportsInterface(bytes4)'),
    ];

    registeredSelectors = registeredSelectors.concat(
      await diamondCut(
        poolDiamond,
        poolImpl.address,
        poolFactory,
        registeredSelectors,
      ),
    );

    pool = PoolMock__factory.connect(poolDiamond.address, admin);
  });

  beforeEach(async () => {
    snapshotId = await ethers.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await ethers.provider.send('evm_revert', [snapshotId]);
  });

  describe('#formatTokenId', () => {
    it('should properly format token id', async () => {
      const operator = '0x1000000000000000000000000000000000000001';
      const tokenId = await pool.formatTokenId(operator, 100, 10000);

      console.log(tokenId.toHexString());

      expect(tokenId.mask(14)).to.eq(100);
      expect(tokenId.shr(14).mask(14)).to.eq(10000);
      expect(tokenId.shr(28).mask(160)).to.eq(operator);
    });
  });

  describe('#parseTokenId', () => {
    it('should properly parse token id', async () => {
      const r = await pool.parseTokenId(
        BigNumber.from('0x010000000000000000000000000000000000000019c40064'),
      );

      expect(r.lower).to.eq(100);
      expect(r.upper).to.eq(10000);
      expect(r.operator).to.eq('0x1000000000000000000000000000000000000001');
    });
  });
});
