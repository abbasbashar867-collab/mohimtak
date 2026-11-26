import type { MetadataRoute } from "next";
import { appUrl } from "@/lib/env";
export default function sitemap(): MetadataRoute.Sitemap {
  const base = appUrl();
  return ["", "/register", "/login", "/forgot", "/legal/terms", "/legal/privacy"].map((p) => ({ url: base + p, lastModified: new Date() }));
}
