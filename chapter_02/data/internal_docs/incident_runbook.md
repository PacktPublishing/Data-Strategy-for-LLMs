# Customer Incident Response (fictional sample)
Owner: Reliability Engineering | Effective: 2026-02-01 | Review: quarterly

## When to open an incident
Open a P1 incident when the customer-facing service is unavailable across regions or customer data integrity is at risk. Use P2 for a partial outage with a viable workaround. Record the start time, affected services, observed symptoms, and a link to the monitoring alert in the incident tracker.

## Response and communication
Page the on-call engineer for P1 immediately; the on-call engineer acknowledges within 15 minutes and names an incident commander. The commander assigns one person to investigate and another to send a customer update within 30 minutes. Updates should state known impact, the next update time, and what remains uncertain. Do not claim a root cause until it is verified.

## Recovery and follow-up
After service is restored, verify the customer journey and monitor error rates for 30 minutes before closing the incident. Attach a timeline and affected customer list to the tracker. Complete a blameless review within two business days, with owners and due dates for follow-up actions.
