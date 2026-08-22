import Foundation

/// Our words for the city's categories, from data/category-labels.json.
///
/// The counterpart of `data/Facts.swift`, and deliberately a different file for
/// a different reason: the facts file is a faithful record of what the city
/// says, and this is where we disagree with it. Decision 0001 keeps those two
/// jobs apart, so an editorial choice can never be mistaken for a fact about
/// the endpoint.
///
/// Only one category is overridden today. The default is the city's own name,
/// and that should stay the common case: a picker that renames everything is a
/// picker nobody can match against the city's own form.
public struct CategoryLabelsFile: Decodable, Equatable {
    public let labels: [String: CategoryLabel]
}

public struct CategoryLabel: Decodable, Equatable {
    /// What the picker shows instead of the city's name.
    public let label: String
    /// One line under it, for a category whose scope is not obvious.
    public let help: String?
}

public enum CategoryLabels {
    public static func parse(_ data: Data) throws -> CategoryLabelsFile {
        try JSONDecoder().decode(CategoryLabelsFile.self, from: data)
    }

    /// The name to show for a category: ours when we have one, the city's
    /// otherwise. Never the slug — a slug on screen is a bug.
    public static func display(_ category: Category, in file: CategoryLabelsFile?) -> String {
        file?.labels[category.slug]?.label ?? category.category
    }

    /// The line under the name, or nil when there is nothing useful to add.
    ///
    /// This replaced the city's general/specific `type`, which both pickers used
    /// to render. That subtitle was the city's internal taxonomy: it said
    /// "Almenn ábending" beneath a category also called "Almenn ábending" (#40),
    /// and it told a walker nothing they could act on.
    public static func help(_ category: Category, in file: CategoryLabelsFile?) -> String? {
        file?.labels[category.slug]?.help
    }
}
