import type { MetadataRoute } from "next";
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "مهمتك | MOHIMTAK", short_name: "مهمتك", start_url: "/", display: "standalone",
    background_color: "#09090b", theme_color: "#2563eb", lang: "ar", dir: "rtl",
    icons: [
      { src: "/brand/icon-192.png", sizes: "192x192", type: "image/png" },
      { src: "/brand/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
  };
}
