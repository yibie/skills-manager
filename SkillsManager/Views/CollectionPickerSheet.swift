import SwiftUI

/// 把某个技能加入分组的选择器;也可当场新建分组。
struct CollectionPickerSheet: View {
    let collections: [CollectionRecord]
    let onPick: (CollectionRecord) -> Void
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isNamingPresented = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(collections, id: \.id) { collection in
                    Button {
                        onPick(collection)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text(collection.name)
                            Spacer()
                            Text("\(collection.memberSkillIDs.count) 个技能")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    isNamingPresented = true
                } label: {
                    Label("新建分组…", systemImage: "plus")
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Add to Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .frame(width: 360, height: 420)
        .alert("新建分组", isPresented: $isNamingPresented) {
            TextField("组名", text: $newName)
            Button("创建") {
                onCreate(newName)
                newName = ""
                dismiss()
            }
            Button("取消", role: .cancel) { newName = "" }
        }
    }
}
