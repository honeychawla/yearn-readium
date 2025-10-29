import { requireNativeComponent, UIManager } from 'react-native';

import type { BaseReadiumViewNativeProps } from '../interfaces';
import { COMPONENT_NAME, LINKING_ERROR } from '../utils';

export const BaseReadiumView =
  UIManager.getViewManagerConfig(COMPONENT_NAME) != null
    ? requireNativeComponent<BaseReadiumViewNativeProps>(COMPONENT_NAME)
    : () => {
        throw new Error(LINKING_ERROR);
      };
