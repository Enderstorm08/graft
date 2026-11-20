import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { AnimatedStatusText } from "@/components/ui/transition-effects";
import { useSlopalyticsGlassSettings } from "@/hooks/use-slopalytics-glass-settings";
import { cn } from "@/lib/utils";

export function SlopalyticsGlassSettings({ variant }: { variant: "popup" | "options" }) {
  const { enabled, setMasterEnabled, status } = useSlopalyticsGlassSettings();
  const isPopup = variant === "popup";
  const id = `${variant}-slopalytics-glass-enabled`;
  return (
    <div className="flex flex-col gap-4">
      <p className={cn("text-muted-foreground leading-relaxed", isPopup ? "text-xs" : "text-sm")}>
        Give Slopalytics frosted panels, softer controls, and a spacious chart layout. Follows the site&apos;s light and dark themes.
      </p>
      <div className="flex items-start justify-between gap-3">
        <Label htmlFor={id} className="cursor-pointer text-sm leading-snug">Enable Slopalytics Glass</Label>
        <Switch id={id} checked={enabled} onCheckedChange={setMasterEnabled} size={isPopup ? "sm" : "default"} className="shrink-0" />
      </div>
      <p className="text-xs leading-relaxed text-muted-foreground">
        Applies to Benchmarks and Usage on slopalytics.com. Charts, data, filters, and exports remain controlled by the site. Turn off to restore its original appearance.
      </p>
      <AnimatedStatusText message={status?.message} isError={status?.isError} className={isPopup ? "text-xs" : "text-sm"} />
    </div>
  );
}
