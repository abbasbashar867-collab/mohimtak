import type { ReactNode } from "react";
import { SubmitButton } from "./SubmitButton";

export function Section({ title, children }: { title: string; children: ReactNode }) {
  return <section className="card mt-5"><h2 className="mb-3 text-lg font-bold">{title}</h2>{children}</section>;
}

/** نموذج إجراء إداري: معرّف + صفحة الرجوع + سبب إلزامي عند الحاجة. */
export function ActionForm({ action, back, hidden, reasonLabel, button, quiet, children }: {
  action: (form: FormData) => Promise<void>; back: string; hidden?: Record<string, string>;
  reasonLabel?: string; button: string; quiet?: boolean; children?: ReactNode;
}) {
  return (
    <form action={action} className="mt-3 flex flex-wrap items-end gap-2">
      <input type="hidden" name="back" value={back} />
      {Object.entries(hidden ?? {}).map(([k, v]) => <input key={k} type="hidden" name={k} value={v} />)}
      {children}
      {reasonLabel && (
        <label className="min-w-52 flex-1"><span className="label">{reasonLabel}</span><input name="reason" required minLength={5} className="field" /></label>
      )}
      <SubmitButton className={quiet ? "btn-quiet" : "btn"}>{button}</SubmitButton>
    </form>
  );
}

export function Field({ label, name, type = "text", defaultValue, required = true, dir }: {
  label: string; name: string; type?: string; defaultValue?: string; required?: boolean; dir?: "ltr";
}) {
  return (
    <label className="min-w-44 flex-1"><span className="label">{label}</span>
      <input name={name} type={type} defaultValue={defaultValue} required={required} dir={dir} className="field" /></label>
  );
}

export function Select({ label, name, defaultValue, options }: { label: string; name: string; defaultValue?: string; options: [string, string][] }) {
  return (
    <label className="min-w-36"><span className="label">{label}</span>
      <select name={name} defaultValue={defaultValue ?? ""} className="field">
        {options.map(([value, text]) => <option key={value} value={value}>{text}</option>)}
      </select></label>
  );
}
