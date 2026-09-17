import { useCallback, useEffect, useRef, useState } from "react";
import type { RequestOptions } from "./api";
import type { ManualOrder } from "./types";

export function useOrderPolling(fetchOrders: (options?: RequestOptions) => Promise<{ orders: ManualOrder[] }>, intervalMs: number) {
  const [orders, setOrders] = useState<ManualOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const active = useRef<AbortController | null>(null);

  const load = useCallback(async () => {
    active.current?.abort();
    const controller = new AbortController();
    active.current = controller;
    try {
      const response = await fetchOrders({ signal: controller.signal });
      if (!controller.signal.aborted) { setOrders(response.orders); setError(null); }
    } catch (reason) {
      if (!controller.signal.aborted) setError(reason instanceof Error ? reason.message : "Could not load orders.");
    } finally {
      if (active.current === controller) { active.current = null; setLoading(false); }
    }
  }, [fetchOrders]);

  const applyOrder = (order: ManualOrder) => {
    // An older poll must not overwrite a mutation that just succeeded.
    active.current?.abort();
    active.current = null;
    setLoading(false);
    setOrders((items) => items.map((item) => item.public_id === order.public_id ? order : item));
  };

  useEffect(() => {
    void load();
    const poll = () => { if (!document.hidden && !active.current) void load(); };
    const timer = window.setInterval(poll, intervalMs);
    document.addEventListener("visibilitychange", poll);
    return () => {
      window.clearInterval(timer);
      document.removeEventListener("visibilitychange", poll);
      active.current?.abort();
      active.current = null;
    };
  }, [load, intervalMs]);

  return { orders, loading, error, setError, load, applyOrder };
}
