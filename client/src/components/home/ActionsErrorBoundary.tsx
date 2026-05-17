import { Component, type ErrorInfo, type ReactNode } from "react";
import type { TranslateFn } from "@/components/home/types";

interface ActionsErrorBoundaryProps {
  children: ReactNode;
  t: TranslateFn;
}

interface ActionsErrorBoundaryState {
  error: Error | null;
}

export class ActionsErrorBoundary extends Component<
  ActionsErrorBoundaryProps,
  ActionsErrorBoundaryState
> {
  state: ActionsErrorBoundaryState = { error: null };

  static getDerivedStateFromError(error: Error): ActionsErrorBoundaryState {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("[ActionsScreen] render failed", {
      message: error.message,
      stack: error.stack,
      componentStack: info.componentStack,
    });
  }

  render() {
    if (!this.state.error) return this.props.children;

    return (
      <div className="fixed inset-x-4 bottom-24 z-[60] rounded-2xl border border-[var(--ep-border)] bg-zinc-950/95 p-4 text-sm text-zinc-200 shadow-2xl">
        <p className="font-bold text-white">
          {this.props.t("actions.panelErrorTitle")}
        </p>
        <p className="mt-1 text-xs text-zinc-400">
          {this.props.t("actions.panelErrorDescription")}
        </p>
        <button
          type="button"
          onClick={() => this.setState({ error: null })}
          className="mt-3 rounded-full bg-white px-4 py-2 text-xs font-black uppercase tracking-[0.12em] text-black"
        >
          {this.props.t("common.close")}
        </button>
      </div>
    );
  }
}
