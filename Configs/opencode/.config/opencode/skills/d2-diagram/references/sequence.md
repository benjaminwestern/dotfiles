# D2 Sequence Diagrams Reference

Complete reference for creating sequence diagrams with spans, groups, notes, and advanced features.

---

**[Back to Main Documentation](../SKILL.md)** | [Shapes](../references/shapes.md) | [Database & UML](../references/database.md) | [Advanced Features](../references/advanced.md) | [Examples](../references/examples.md)

## Basic Sequence Diagram

Set `shape: sequence_diagram` for lifeline-based diagrams:

```d2
shape: sequence_diagram

User: {shape: person}
Frontend: Frontend (React)
Backend: Backend (API)
Database: {shape: cylinder}

User -> Frontend: click button
Frontend -> Backend: POST /api/data
Backend -> Database: SELECT * FROM table
Database --> Backend: results
Backend --> Frontend: JSON response
Frontend --> User: display data
```

## Key Rules

1. **Scoping**: Children share the same scope throughout the sequence diagram
2. **Ordering**: Order matters - objects appear in the order defined

## Spans (Activation Bars)

```d2
shape: sequence_diagram

alice: Alice
bob: Bob

alice -> bob: What does it mean
bob.span: {
  start: to be well-adjusted?
  end: The ability to play bridge
}
```

## Groups (Fragments)

```d2
shape: sequence_diagram

alice: Alice
bob: Bobby

# Define actors first
alice -> bob: uhm, hi
bob -> alice: oh, hello

# Then create groups
group shower thoughts: {
  alice -> bob: what did you have for lunch?
  bob -> alice: that's personal
}
```

## Notes

```d2
shape: sequence_diagram

alice: Alice
bob: Bob

alice -> bob: request
bob.note: This is a note about the request
bob --> alice: response
```

## Self-messages

```d2
shape: sequence_diagram

actor -> actor: self message
```

## Styling with Classes

```d2
shape: sequence_diagram

classes: {
  actor: {
    shape: person
    style.fill: "#3b82f6"
    style.stroke: "#1d4ed8"
  }
  service: {
    shape: rectangle
    style.fill: "#10b981"
    style.stroke: "#059669"
  }
  database: {
    shape: cylinder
    style.fill: "#f59e0b"
    style.stroke: "#d97706"
  }
}

User: {class: actor}
Frontend: {class: service}
Database: {class: database}
```

**Multiple classes:**
```d2
myshape: {class: [class1, class2]}
```

**Connection classes:**
```d2
classes: {
  dashed: {
    style.stroke-dash: 5
  }
}

x -> y: {class: dashed}
```

## Connection Chaining

```d2
shape: sequence_diagram

alice -> bob -> charlie: Message flows through
```

## Professional Sequence Diagram Example

```d2
shape: sequence_diagram

direction: right

classes: {
  professional-person: {
    shape: person
    style.fill: "#66CAD8"
    style.stroke: "#2A2A33"
  }
  professional-service: {
    style.fill: "#9FA7D0"
    style.stroke: "#2A2A33"
  }
  professional-database: {
    shape: cylinder
    style.fill: "#E82370"
    style.stroke: "#2A2A33"
  }
}

User: {class: professional-person}
Frontend: {class: professional-service}
Backend: {class: professional-service}
Database: {class: professional-database}

User -> Frontend: Login request
Frontend -> Backend: POST /api/login
Backend -> Database: Verify credentials
Database --> Backend: User data
Backend --> Frontend: Auth token
Frontend --> User: Login success
```
