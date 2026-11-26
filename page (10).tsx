import { AutoRefresh } from "@/components/AutoRefresh";
import { SiteHeader } from "@/components/SiteHeader";
import { requireDestination } from "@/lib/auth/session";
import { getI18n } from "@/lib/i18n/server";

export default async function StatusPage() {
  const { profile } = await requireDestination("/account/status");
  const { t } = await getI18n();
  const status = profile?.status;
  const body = !status ? t.status.incomplete
    : status === "pending" ? t.status.pendingText : status === "rejected" ? t.status.rejectedText
    : status === "suspended" ? t.status.suspendedText : status === "banned" ? t.status.bannedText : "";
  return (
    <>
      <SiteHeader signedIn />
      <main className="mx-auto max-w-lg px-4 py-10">
        {status === "pending" && <AutoRefresh seconds={20} />}
        <div className="card space-y-3">
          <h1 className="text-2xl font-bold">{t.status.title}</h1>
          {status && <span className="chip chip-on">{t.status[status]}</span>}
          <p>{body}</p>
          {profile?.status_reason && <p className="notice notice-bad">{t.status.reason}: {profile.status_reason}</p>}
        </div>
      </main>
    </>
  );
}
