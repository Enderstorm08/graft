import { useCallback, useEffect, useState } from "react";

export function useSlopalyticsGlassSettings() {
  const [enabled, setEnabled] = useState(false);
  const [status, setStatus] = useState<{ message: string; isError?: boolean } | null>(null);
  useEffect(() => {
    let mounted = true;
    let changed = false;
    const onChange: Parameters<typeof chrome.storage.onChanged.addListener>[0] = (changes, area) => {
      if (area === "sync" && "slopalyticsGlassEnabled" in changes) {
        changed = true;
        setEnabled(changes.slopalyticsGlassEnabled.newValue === true);
      }
    };
    chrome.storage.onChanged.addListener(onChange);
    chrome.storage.sync.get({ slopalyticsGlassEnabled: false }, (stored) => {
      const error = chrome.runtime.lastError;
      if (!mounted) return;
      if (error) setStatus({ message: "Could not load settings.", isError: true });
      else if (!changed) setEnabled(stored.slopalyticsGlassEnabled === true);
    });
    return () => { mounted = false; chrome.storage.onChanged.removeListener(onChange); };
  }, []);
  const setMasterEnabled = useCallback((value: boolean) => {
    chrome.storage.sync.set({ slopalyticsGlassEnabled: value }, () => {
      if (chrome.runtime.lastError) {
        setStatus({ message: "Could not save settings.", isError: true });
        return;
      }
      setEnabled(value);
      setStatus({ message: value ? "Glass styling enabled." : "Original styling restored." });
    });
  }, []);
  return { enabled, setMasterEnabled, status };
}
