import type { NextRequest } from "next/server";
import { servePrivateImage } from "@/lib/security/private-file";

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  return servePrivateImage(request, (await params).id, "log_document_view", "p_document_id", "identity-documents");
}
