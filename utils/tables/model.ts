import fs from 'fs';
import _ from 'lodash';
import * as prettier from 'prettier';
import { render } from 'mustache';
import {
  BlockExplorerUrl,
  ChainName,
  ContractKey,
  DeploymentMetadata,
  DeploymentPath,
} from '../deployment/types';
import { Network } from '@ethersproject/networks';
import { getContractFilePath } from '../deployment/deployment';
import {
  tableTemplateNoHeader,
  tableTemplate,
  summaryPartial,
  detailedSummaryPartial,
} from './template';
import { TableData, Contract, CoreContractMetaData } from './types';

function displayHeader() {
  if (this.name.length > 0 || this.name !== '') return `|**${this.name}**|||||`;
  else return '||||||';
}

function displayAddress() {
  if (this.address.length > 0 || this.address !== '')
    return `\`${this.address}\``;
  else return '';
}

function displayEtherscanUrl() {
  if (this.address.length > 0 || this.address !== '')
    return `[🔗](${this.etherscanUrl}/address/${this.address})`;
  else return '';
}

function displayFilePathUrl() {
  if (this.commitHash.length > 0 || this.commitHash !== '') {
    const contractFilePath = getContractFilePath(this.name);
    return `[📁](https://github.com/Premian-Labs/premia-v3-contracts-private/blob/${this.commitHash}/${contractFilePath})`;
  } else return '';
}

let tableView: TableData = {
  categories: {
    vaults: {
      name: 'Vault',
      chain: '',
      sections: [],
      displayHeader,
    },
    optionPS: {
      name: 'Physically Settled Option',
      chain: '',
      sections: [],
      displayHeader,
    },
    optionReward: {
      name: 'Option Reward',
      chain: '',
      sections: [],
      displayHeader,
    },
    core: {
      name: 'Core Contract',
      chain: '',
      sections: [],
      displayHeader,
    },
  },
};

export async function generateTables(network: Network) {
  const chain = ChainName[network.chainId];
  const etherscanUrl = BlockExplorerUrl[network.chainId];
  const deploymentPath = DeploymentPath[network.chainId];

  const deploymentMetadata = JSON.parse(
    fs.readFileSync(`${deploymentPath}/metadata.json`).toString(),
  ) as DeploymentMetadata;

  updateTableView(deploymentMetadata, chain, etherscanUrl);
  writeTables(deploymentPath, chain);
}

function updateTableView(
  deploymentMetadata: DeploymentMetadata,
  chain: string,
  etherscanUrl: string,
) {
  for (const key in deploymentMetadata) {
    if (
      chain !== 'Arbitrum Nova' &&
      (key === 'vaults' || key === 'optionReward' || key === 'optionPS')
    ) {
      const category = tableView.categories[key];
      category.chain = chain;

      category.sections.push({
        name: '',
        contracts: [],
      });

      for (let contract in deploymentMetadata[key]) {
        let contractData = deploymentMetadata[key][contract];

        let contractInfo: Contract = {
          name: contract,
          description: '',
          address: contractData.address,
          etherscanUrl,
          displayAddress,
          displayEtherscanUrl,
        };

        category.sections[0].contracts.push(contractInfo);
      }
    } else if (key in ContractKey) {
      const category = tableView.categories.core;
      category.chain = chain;

      const contractMetadata = CoreContractMetaData[key];

      let sectionIndex = _.findIndex(category.sections, [
        'name',
        contractMetadata.section,
      ]);

      if (sectionIndex === -1) {
        category.sections.push({
          name: contractMetadata.section,
          contracts: [],
        });

        sectionIndex = category.sections.length - 1;
      }

      let contractData = deploymentMetadata[key as ContractKey];

      let contractInfo: Contract = {
        name: contractMetadata.name,
        description: '',
        address: contractData.address,
        commitHash: contractData.commitHash,
        etherscanUrl,
        displayAddress,
        displayEtherscanUrl,
        displayFilePathUrl,
      };

      category.sections[sectionIndex].contracts.push(contractInfo);
    }
  }

  return tableView;
}

function writeTables(deploymentPath: string, chain: string) {
  for (const key in tableView.categories) {
    const category = tableView.categories[key];

    let template = tableTemplate;
    let partial = detailedSummaryPartial;
    let pathKey = 'core';

    if (
      chain !== 'Arbitrum Nova' &&
      (key === 'vaults' || key === 'optionReward' || key === 'optionPS')
    ) {
      template = tableTemplateNoHeader;
      partial = summaryPartial;
      pathKey = key;
    }

    // Generate md file from template
    let table = render(template, category, { partial });

    // Prettify table markdown
    table = prettier.format(table, { parser: 'markdown' });

    // Overwrite {pathKey}Table.md
    const tablePath = `${deploymentPath}/${pathKey}Table.md`;
    fs.writeFileSync(tablePath, table);
    console.log(`Table generated at ${tablePath}`);
  }
}
