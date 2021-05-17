local M = {}

function M.get_action_params(item, uri)
    local bufnr = vim.uri_to_bufnr(uri)

    local start_pos = {line = item.start_line, character = item.start_col + 2}
    local diagnostics = vim.lsp.diagnostic.get_line_diagnostics(bufnr,
                                                                item.start_line)

    return {
        textDocument = {uri = uri},
        range = {start = start_pos, ["end"] = start_pos},
        context = {diagnostics = diagnostics},
        bufnr = bufnr
    }
end

return M
