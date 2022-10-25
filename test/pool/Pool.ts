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
      const tokenId = await pool.formatTokenId(
        operator,
        1,
        parseEther('0.1'),
        parseEther('0.2'),
      );

      expect(tokenId.mask(2)).to.eq(1);
      expect(tokenId.shr(2).mask(47)).to.eq(parseUnits('0.1', 14));
      expect(tokenId.shr(49).mask(47)).to.eq(parseUnits('0.2', 14));
      expect(tokenId.shr(96).mask(160)).to.eq(operator);
    });
  });

  describe('#parseTokenId', () => {
    it('should properly parse token id', async () => {
      const r = await pool.parseTokenId(
        BigNumber.from(
          '0x1000000000000000000000000000000000000001246139ca8000246139ca8001',
        ),
      );

      expect(r.rangeSide).to.eq(1);
      expect(r.lower).to.eq(parseEther('0.1'));
      expect(r.upper).to.eq(parseEther('0.2'));
      expect(r.operator).to.eq('0x1000000000000000000000000000000000000001');
    });
  });
});
