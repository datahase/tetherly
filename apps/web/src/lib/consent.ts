// Regions where analytics cookies need opt-in consent: the EU, the rest of the EEA, the UK and Switzerland.
const optIn = new Set([
  "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL",
  "PL", "PT", "RO", "SK", "SI", "ES", "SE", // EU
  "IS", "LI", "NO", // EEA
  "GB", "CH",
]);

/** Unknown country (no geo header, e.g. local dev) is treated as needing consent. */
export const needsConsent = (country: string | null | undefined) => !country || optIn.has(country.toUpperCase());

/** Readable by the page: "consent" or "open". Holds no personal data. */
export const REGION_COOKIE = "tl_region";
