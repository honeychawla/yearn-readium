import type { Link } from './Link';
import type { Locator } from './Locator';

export interface File {
  /**
   * A string path to an eBook on disk.
   */
  url: string;

  /**
   * An optional location that the eBook will be opened at.
   */
  initialLocation?: Locator | Link;

  /**
   * An optional passphrase for LCP-protected EPUBs.
   * If provided, Readium will use this to decrypt without prompting the user.
   */
  lcpPassphrase?: string;
}
