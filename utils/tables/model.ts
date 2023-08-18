import fs from 'fs';
import _ from 'lodash';
import * as prettier from 'prettier';
import { render } from 'mustache';
import {
  BlockExplorerUrl,
  ChainName,
  ContractKey,
  ContractType,
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
import {
  TableData,
  Contract,
  CoreContractMetaData,
  DescriptionOverride,
} from './types';

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
  if (
    (this.commitHash.length > 0 || this.commitHash !== '') &&
    (this.filePath.length > 0 || this.filePath !== '')
  ) {
    return `[📁](https://github.com/Premian-Labs/premia-v3-contracts-private/blob/${this.commitHash}/${this.filePath})`;
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
    // Update Vaults, OptionReward, and OptionPS views
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
        const contractData = deploymentMetadata[key][contract];

        const contractInfo: Contract = {
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
      // Update Core view
      const category = tableView.categories.core;
      category.chain = chain;

      const contractMetadata = CoreContractMetaData[key];
      const filePath = getContractFilePath(contractMetadata.name);
      let section = filePath.split('/')[1];
      // Capitalize first letter of section
      section = section.charAt(0).toUpperCase() + section.slice(1);

      let sectionIndex = _.findIndex(category.sections, ['name', section]);

      if (sectionIndex === -1) {
        category.sections.push({
          name: section,
          contracts: [],
        });

        sectionIndex = category.sections.length - 1;
      }

      const contractData = deploymentMetadata[key as ContractKey];

      const contractInfo: Contract = {
        name: contractMetadata.name,
        description: getContractDescription(key, contractData.contractType),
        address: contractData.address,
        commitHash: contractData.commitHash,
        etherscanUrl,
        filePath,
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

function getContractDescription(
  contractKey: string,
  contractType: ContractType | string,
) {
  const override = DescriptionOverride[contractKey];
  if (override) return override;

  let name = addSpaceBetweenUpperCaseLetters(contractKey);

  // remove the contract type from the name, if it's there
  const typeInName = name.split(' ').pop() === contractType;
  if (typeInName) name = name.split(' ').slice(0, -1).join(' ');
  const type = addSpaceBetweenUpperCaseLetters(contractType);

  return `${name} ${type}`;
}

function addSpaceBetweenUpperCaseLetters(s: string) {
  return s.replace(/([a-z])([A-Z])/g, '$1 $2');
}
